# JOB-12: "On my way". Someone going on a visit booked for today tells the client when they'll
# arrive: their visit page shows an "On the way" card at once, and they get an email the first
# time and again when the time moves 10+ minutes from the one last emailed. The card stays an hour
# past the time ("any minute"), and goes when the visit starts, ends or moves.
#
#   arrives_at = visit.on_the_way_arrival(minutes: 30)        # now + 30, to the nearest 5 minutes
#   visit.on_the_way_warning(arrives_at)                      # "That's after the 9 am–12 pm window", or nil
#   visit.send_on_the_way!(arrives_at, by: user)              # => OnTheWay::Sent
module OnTheWay
  extend ActiveSupport::Concern

  MINUTES = [ 15, 30, 45, 60 ].freeze
  MIN_AHEAD = 5.minutes # a picked time
  EXACT_SLACK = 15.minutes # from an exact start, before it warns
  UPDATE_EMAIL_MINUTES = 10 # from the time in the last email, before an update is emailed
  SHOWN_AFTER = 1.hour
  PER_DAY = 5

  class Refused < StandardError; end

  # emailed: whether an email is on its way; why_not: nil, "small_change", "no_email" or "email_limit".
  Sent = Data.define(:arrives_at, :emailed, :why_not, :first)

  included do
    belongs_to :on_the_way_by, class_name: "User", optional: true
  end

  # Times are on the clock where the work is (CAT-07), rounded to the nearest 5 minutes
  # (10:47 + 30 is 11:15). A picked time ("HH:MM") is rounded up to the next 5 minutes and must
  # then be later today and 5+ minutes ahead. `arrives_at` is a time already chosen (ISO 8601,
  # UTC: "Send anyway" after a warning), so a repeated hour on a DST change stays the one picked.
  def on_the_way_arrival(minutes: nil, at: nil, arrives_at: nil, now: Time.current)
    now = now.in_time_zone(time_zone)
    if arrives_at.present?
      arrival = (Time.iso8601(arrives_at.to_s) rescue nil)&.in_time_zone(time_zone)
      raise Refused, "Choose the time again." unless arrival && arrival.min % 5 == 0 && arrival.sec.zero? && arrival > now
    elsif at.present?
      raise Refused, "Choose a time like 11:30." unless ArrivalTiming::CLOCK.match?(at.to_s.strip)

      picked = time_zone.local(now.year, now.month, now.day, *at.to_s.strip.first(5).split(":").map(&:to_i))
      arrival = picked + ((5 - (picked.min % 5)) % 5).minutes
      raise Refused, "Choose a time at least #{MIN_AHEAD.in_minutes.to_i} minutes from now." if arrival < now + MIN_AHEAD
    else
      raise Refused, "Choose how long you'll be." unless MINUTES.include?(minutes.to_i)

      arrival = OnTheWay.round_to_five(now + minutes.to_i.minutes)
    end
    raise Refused, "That's tomorrow. Send it then, or call the client." unless arrival.to_date == now.to_date

    arrival
  end

  def self.round_to_five(time)
    time = time.change(sec: 0)
    off = time.min % 5
    off < 3 ? time - off.minutes : time + (5 - off).minutes
  end

  # Outside the arrival window, or 15+ minutes from an exact start. Anytime visits don't warn.
  def on_the_way_warning(arrives_at)
    case timing
    when "window"
      window = time_label.delete_prefix("Arrive ")
      if arrives_at > window_ends_at then "That's after the #{window} window."
      elsif arrives_at < starts_at then "That's before the #{window} window."
      end
    when "exact"
      start = time_label
      if arrives_at - starts_at >= EXACT_SLACK then "That's #{minutes_between(arrives_at, starts_at)} after the #{start} start."
      elsif starts_at - arrives_at >= EXACT_SLACK then "That's #{minutes_between(arrives_at, starts_at)} before the #{start} start."
      end
    end
  end

  # Whether `user` gets the button: someone going on a visit booked (not started, completed or
  # cancelled) for today where the work is, while the business sends "On my way". Erased clients
  # (INS-02) get none.
  def on_the_way_offered_to?(user)
    user.present? && status == "scheduled" && scheduled_on == time_zone.today && business.client_visit_email?("on_my_way") &&
      assignments.any? { _1.user_id == user.id } && !job.client.erased?
  end

  # Why another send isn't allowed now, or nil: one a minute and PER_DAY a day per visit.
  def on_the_way_limit(now: Time.current)
    sends = events.where(kind: "on_the_way")
    if sends.where("occurred_at > ?", now - 1.minute).exists?
      "You sent this less than a minute ago. Try again in a moment."
    elsif sends.where(occurred_at: now.in_time_zone(time_zone).beginning_of_day..).count >= PER_DAY
      "That's #{PER_DAY} for this visit today, the most there can be. Call or text the client if the time changes again."
    end
  end

  # The card's on the client's visit page from the first send until an hour past the time, while
  # the visit is still booked.
  def on_the_way?(now: Time.current) = status == "scheduled" && on_the_way_arrives_at.present? && now < on_the_way_arrives_at + SHOWN_AFTER
  def on_the_way_late?(now: Time.current) = on_the_way?(now:) && now >= on_the_way_arrives_at

  # "11:15 am", on the clock where the work is.
  def on_the_way_time_label(time = on_the_way_arrives_at) = clock_label(time)

  # The client's usable address: none, or one refused or blocked, isn't emailed.
  def on_the_way_email
    email = job.client.primary_email
    email if email && email.undeliverable_at.nil? && !EmailSuppression.suppressed?(email.value)
  end

  # Records the time (the card shows it at once), who sent it and, in the visit's history, whether
  # an email went. Emails the first time, then when the time is UPDATE_EMAIL_MINUTES+ from the
  # one last emailed, if the client has a usable address and the business's hourly client email
  # budget allows (ClientEmailBudget).
  def send_on_the_way!(arrives_at, by:)
    with_lock do
      raise Refused, "On my way is only for a visit booked for today that hasn't started." unless on_the_way_offered_to?(by)
      if (limit = on_the_way_limit) then raise Refused, limit end

      first = !on_the_way?
      emailed_for = (on_the_way_emailed_arrives_at unless first)
      why_not = if emailed_for && (arrives_at - emailed_for).abs < UPDATE_EMAIL_MINUTES.minutes then "small_change"
      elsif on_the_way_email.nil? then "no_email"
      elsif !ClientEmailBudget.take(business) then "email_limit"
      end
      update_columns(on_the_way_arrives_at: arrives_at, on_the_way_by_id: by.id, updated_at: Time.current,
                     on_the_way_emailed_arrives_at: why_not ? emailed_for : arrives_at)
      VisitEvent.record!(self, :on_the_way, by:, arrives_at: arrives_at.utc.iso8601, emailed: why_not.nil?, why_not:)
      ClientEvent.record!(job.client, :visit_on_the_way, subject: self, by:, arrives_at: arrives_at.utc.iso8601) if first # CLI-05
      email_on_the_way(emailed_before: emailed_for.present?) unless why_not
      Sent.new(arrives_at, why_not.nil?, why_not, first)
    end
  end

  # Starting, completing, cancelling or moving the visit takes the card away, with no email.
  def clear_on_the_way
    return unless on_the_way_arrives_at

    update_columns(on_the_way_arrives_at: nil, on_the_way_emailed_arrives_at: nil, on_the_way_by_id: nil)
  end

  private

  # The first email, or "Updated arrival time" once one has gone. It's about the job, so it's
  # listed there (NTF-01) and replies go to the job's location (CAT-07).
  def email_on_the_way(emailed_before:)
    VisitMailer.send_later(:on_the_way, business:, to: on_the_way_email.value, kind: emailed_before ? "visit_on_the_way_update" : "visit_on_the_way",
                                        related: job, job_id: job.id, visit_id: id, arrives_at: on_the_way_arrives_at.utc.iso8601)
  end

  def minutes_between(one, other)
    hours, minutes = ((one - other).abs / 60).round.divmod(60)
    [ ("#{hours} hour#{"s" if hours > 1}" if hours.positive?), ("#{minutes} minutes" if minutes.positive?) ].compact.join(" ")
  end
end
