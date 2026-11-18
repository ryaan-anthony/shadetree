# One trip to do a job's work (JOB-02), on one date: at a start time, in an arrival window
# ("arrive 8–10"), or anytime that day; with an estimated duration, the members going, and its
# own instructions. Times are entered as wall-clock times in the business's zone and stored in
# UTC; a visit's times are always on its own date there.
#
# Changes go through #reschedule!, #cancel!, #restore! and #complete!, which record who did
# what (VisitEvent) and update the job's status (Job#refresh_status!).
class Visit < ApplicationRecord
  include BusinessOwned

  TIMINGS = %w[exact window anytime].freeze
  STATUSES = %w[scheduled in_progress completed cancelled].freeze
  OPEN_STATUSES = %w[scheduled in_progress].freeze
  LABELS = { "scheduled" => "Scheduled", "in_progress" => "In progress", "completed" => "Completed", "cancelled" => "Cancelled" }.freeze
  MAX_DURATION = 24 * 60
  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d(:00)?\z/ # "HH:MM" from a time field (browsers may add ":00")

  MAX_DAYS = 31 # visits booked at once

  class NotOpen < StandardError; end
  class BadDates < ArgumentError; end

  belongs_to_business_record :job
  belongs_to :created_by, class_name: "User", optional: true
  has_many :assignments, class_name: "VisitAssignment", inverse_of: :visit, dependent: :delete_all
  has_many :assignees, -> { order(:first_name, :last_name, :email) }, through: :assignments, source: :user
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "VisitEvent", inverse_of: :visit, dependent: :delete_all
  has_many :notes, -> { order(:created_at, :id) }, class_name: "VisitNote", inverse_of: :visit, dependent: :delete_all # JOB-04

  normalizes :instructions, with: ->(value) { value.to_s.strip.presence }
  normalizes :cancel_reason, with: ->(value) { value.to_s.squish.presence }

  validates :scheduled_on, presence: true
  validates :timing, inclusion: { in: TIMINGS }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_minutes, numericality: { only_integer: true, in: 5..MAX_DURATION, message: "must be between 5 minutes and 24 hours" }
  validates :instructions, length: { maximum: 2_000 }
  validates :client_note, length: { maximum: 1_000 } # JOB-05: for the client, in their emails and on their page
  validates :cancel_reason, length: { maximum: 200 }
  validate :times_make_sense
  validate :assignees_are_members

  before_validation :place_times

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :in_order, -> { order(:scheduled_on, Arel.sql("starts_at NULLS LAST"), :id) }
  scope :upcoming, ->(today) { open.where(scheduled_on: today..) }

  # Form fields: wall-clock times ("09:00") and the duration in hours ("1.5").
  attr_writer :start_time, :window_end_time

  def start_time = @start_time || clock(starts_at)
  def window_end_time = @window_end_time || clock(window_ends_at)

  def duration_hours = (duration_minutes.to_d / 60).round(2).to_s("F").sub(/\.0\z/, "")

  def duration_hours=(value)
    hours = BigDecimal(value.to_s.strip, exception: false)
    self.duration_minutes = hours && (hours * 60).round
  end

  # Members going, from the form's checkboxes (user ids). Checked against the business's
  # active members on validation.
  def assignee_ids=(ids)
    @assignee_ids = Array(ids).compact_blank.map(&:to_i).uniq
  end

  def assignee_ids = @assignee_ids || assignments.map(&:user_id)

  # Whether the time, day, duration or crew differ from what's saved (what warnings are about).
  def when_or_crew_changed?
    (changes.keys & %w[scheduled_on timing starts_at window_ends_at duration_minutes]).any? ||
      (!@assignee_ids.nil? && @assignee_ids.sort != assignments.map(&:user_id).sort)
  end

  def status_label = LABELS.fetch(status)
  def open? = OPEN_STATUSES.include?(status)
  def anytime? = timing == "anytime"
  def window? = timing == "window"

  # When the work is expected to finish: the start (or the window's end) plus the duration.
  def ends_at = starts_at && ((window_ends_at || starts_at) + duration_minutes.minutes)

  # "9 am", "Arrive 8–10 am", "Anytime".
  def time_label
    case timing
    when "exact" then clock_label(starts_at)
    when "window"
      same_half = starts_at.in_time_zone(business.time_zone).hour < 12 == window_ends_at.in_time_zone(business.time_zone).hour < 12
      "Arrive #{clock_label(starts_at, ampm: !same_half)}–#{clock_label(window_ends_at)}"
    else "Anytime"
    end
  end

  # "Tue, Nov 17 · Arrive 8–10 am"
  def when_label(with_year: false) = "#{scheduled_on.strftime("%a, %b %-d")}#{", #{scheduled_on.year}" if with_year || scheduled_on.year != business.today.year} · #{time_label}"

  def duration_label
    hours, minutes = duration_minutes.divmod(60)
    [ ("#{hours} h" if hours.positive?), ("#{minutes} min" if minutes.positive?) ].compact.join(" ")
  end

  # A new visit with its assignees, recorded and reflected in the job's status.
  def schedule!(by:, notify_client: true) = self.class.schedule_all!([ self ], by:, notify_client:).first

  # After a visit opens again (booked, restored, reopened), finishing the job's visits tells the
  # office again; until then it's told once.
  def reset_ready_to_invoice
    job.update_columns(ready_to_invoice_notified_at: nil) if job.ready_to_invoice_notified_at
  end

  # Several visits for one job at once (multi-day work: one visit per date), under one lock on
  # the job; the people going hear about them in one notification each.
  def self.schedule_all!(visits, by:, notify_client: true)
    job = visits.first.job
    job.with_lock do
      raise NotOpen, "#{job.number} is #{job.status_label.downcase}. Reopen it to change its visits." unless job.open?

      visits.each do |visit|
        visit.save!
        visit.sync_assignments
        VisitEvent.record!(visit, :scheduled, by:, to: visit.snapshot, crew: visit.crew_names, crew_ids: visit.assignees.map(&:id))
      end
      visits.first.reset_ready_to_invoice
      job.refresh_status!
      visits.first.tell_client(notify_client, visits)
    end
    crew = visits.flat_map { _1.assignees.to_a }.uniq
    dates = visits.size == 1 ? visits.first.when_label : "#{visits.size} days (#{visits.map { _1.scheduled_on.strftime("%b %-d") }.to_sentence}), #{visits.first.time_label}"
    visits.first.notify_crew("visit_assigned", crew, "You're on #{job.title} (#{job.number}): #{dates}", by:)
    visits
  end

  # The days to book from the form: the first day, then every day through a last day (skipping
  # days the business is closed, if asked) and other days picked one by one. Stops one past
  # MAX_DAYS (so "too many" can be reported) however far away the last day is. Raises
  # BadDates for a last day before the first.
  def self.plan_dates(first, through: nil, extra: [], skip_closed: false, hours: nil)
    first = parse_date(first) or return []
    last = parse_date(through)
    raise BadDates, "The last day is before the first." if last && last < first

    dates = [ first ]
    day = first + 1
    while last && day <= last && dates.size <= MAX_DAYS
      dates << day unless skip_closed && hours && !hours.open_on?(day)
      day += 1
    end
    dates += Array(extra).first(MAX_DAYS + 1).filter_map { parse_date(_1) }
    dates.uniq.sort.first(MAX_DAYS + 1)
  end

  # Only YYYY-MM-DD, as date fields send (Date.parse would read "Nov" as Nov 1).
  def self.parse_date(value) = (Date.iso8601(value.to_s) if value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)) rescue nil

  # Date, time, duration, crew or instructions changed; records what changed and who changed it.
  # A change to the crew alone still changes the visit's row, so lock_version catches a stale form.
  def reschedule!(attributes, by:, notify_client: true)
    under_job_lock do
      lock!
      raise NotOpen, "This visit is #{status_label.downcase}." unless open?

      before, before_crew, before_duration = snapshot, assignees.to_a, duration_minutes
      assign_attributes(attributes)
      crew_changed = !@assignee_ids.nil? && @assignee_ids.sort != before_crew.map(&:id).sort
      self.updated_at = Time.current if crew_changed && !changed?
      details = (changes.keys & %w[duration_minutes instructions])
      save!
      sync_assignments
      after_crew = assignees.reload.to_a
      moved = snapshot.except("when") != before.except("when")
      VisitEvent.record!(self, :rescheduled, by:, from: before, to: snapshot) if moved
      tell_client(notify_client) if moved
      added, removed = after_crew - before_crew, before_crew - after_crew
      if added.any? || removed.any?
        VisitEvent.record!(self, :reassigned, by:, added: added.map(&:full_name), removed: removed.map(&:full_name),
                                               added_ids: added.map(&:id), removed_ids: removed.map(&:id))
      end
      VisitEvent.record!(self, :updated, by:, changed: details, duration_from: before_duration, duration_to: duration_minutes) if details.any?

      notify_crew("visit_assigned", added, "You're on #{job.title} (#{job.number}): #{when_label}", by:)
      notify_crew("visit_changed", removed, "You're no longer on #{job.title} (#{job.number}) on #{before["when"].sub(/, #{business.today.year} ·/, " ·")}", by:,
                  path: Rails.application.routes.url_helpers.admin_my_day_path) # the visit isn't theirs to open any more
      if moved || details.any?
        what = details.map { { "duration_minutes" => "duration", "instructions" => "instructions" }.fetch(_1) }.to_sentence
        title = moved ? "Moved: #{job.title} (#{job.number}) is now #{when_label}" : "New #{what}: #{job.title} (#{job.number}), #{when_label}"
        notify_crew("visit_changed", after_crew - added, title, by:, body: (instructions if details.include?("instructions")))
      end
    end
  end

  # Cancelling the last open visit of a job whose other visits were done also means it's ready
  # to invoice.
  def cancel!(by:, reason: nil, notify_client: true)
    under_job_lock do
      lock!
      finish!("cancelled", by:, reason:)
      notify_ready_to_invoice(by:) if !job.visits.open.exists? && job.visits.where(status: "completed").exists?
      tell_client(notify_client)
    end
  end

  def restore!(by:, notify_client: true)
    under_job_lock do
      lock!
      raise NotOpen, "This visit isn't cancelled." unless status == "cancelled"

      update!(status: "scheduled", cancelled_at: nil, cancel_reason: nil)
      VisitEvent.record!(self, :restored, by:)
      reset_ready_to_invoice
      tell_client(notify_client)
      notify_crew("visit_assigned", assignees.to_a, "Back on: #{job.title} (#{job.number}), #{when_label}", by:)
    end
  end

  # On site (JOB-04): the person going starts the visit.
  def start!(by:)
    under_job_lock do
      lock!
      raise NotOpen, "This visit is #{status_label.downcase}." unless status == "scheduled"

      update!(status: "in_progress", started_at: Time.current)
      VisitEvent.record!(self, :started, by:)
    end
  end

  # Done (staff from the job page; the people going from their day view, JOB-04). Completing a
  # job's last open visit tells the office it's ready to invoice.
  def complete!(by:)
    under_job_lock do
      lock!
      finish!("completed", by:)
      notify_ready_to_invoice(by:) unless job.visits.open.exists?
    end
  end

  # A visit completed by mistake can be reopened the same day (by the business's clock).
  def reopenable? = status == "completed" && job.open? && completed_at && completed_at.in_time_zone(business.time_zone).to_date == business.today

  def reopen!(by:)
    under_job_lock do
      lock!
      raise NotOpen, "Only a visit completed today can be reopened." unless reopenable?

      update!(status: started_at ? "in_progress" : "scheduled", completed_at: nil)
      VisitEvent.record!(self, :reopened, by:)
      reset_ready_to_invoice
    end
  end

  # Ends an open visit as completed or cancelled. Callers hold the job's and the visit's locks
  # (Job#complete! and #cancel! lock their open visits up front, and tell the crew once
  # themselves rather than per visit).
  def finish!(status, by:, reason: nil, notify: true)
    raise NotOpen, "This visit is already #{status_label.downcase}." unless open?

    if status == "completed"
      update!(status:, completed_at: Time.current)
      VisitEvent.record!(self, :completed, by:)
    else
      update!(status:, cancelled_at: Time.current, cancel_reason: reason)
      VisitEvent.record!(self, :cancelled, by:, reason: cancel_reason)
      notify_crew("visit_cancelled", assignees.to_a, "Cancelled: #{job.title} (#{job.number}), #{when_label}", by:, body: cancel_reason) if notify
    end
  end

  # NTF-02: tells the people going (not whoever made the change). The notification opens the
  # job for those who can see jobs, and the visit in their day view (JOB-04) for everyone else.
  def notify_crew(kind, users, title, by:, body: nil, path: nil)
    users = Array(users).reject { _1.id == by&.id }
    return if users.empty?

    paths = Rails.application.routes.url_helpers
    office = business.business_users.active.where(user: users).select { _1.can?(:office) }.map(&:user_id)
    users.partition { office.include?(_1.id) }.zip([ paths.admin_job_path(job), path || paths.admin_my_visit_path(self) ]).each do |group, path|
      NotificationType.deliver(kind, business:, subject: self, actor: by, to: group, title:, body:, path:) if group.any?
    end
  end

  # JOB-04: the office hears that a job's visits are all done, once until a visit opens again.
  def notify_ready_to_invoice(by:)
    return if job.ready_to_invoice_notified_at

    job.update_columns(ready_to_invoice_notified_at: Time.current)
    NotificationType.deliver("job_ready_to_invoice", business:, subject: job, actor: by,
                             title: "#{job.title} (#{job.number}) is ready to invoice", body: "#{by&.full_name || "The crew"} completed the last visit.",
                             path: Rails.application.routes.url_helpers.admin_job_path(job))
  end

  # When it is, as shown ("when") and as values, for the history and for later notices.
  # JOB-05: what the client would be told about this visit: booked (and when) or cancelled.
  def client_state
    { "state" => status == "cancelled" ? "cancelled" : "booked", "when" => when_label(with_year: true), "on" => scheduled_on.iso8601,
      "timing" => timing, "starts_at" => starts_at&.utc&.iso8601, "window_ends_at" => window_ends_at&.utc&.iso8601 }
  end

  # Whether the client has been told about the visit as it is now ("when" is only the label).
  def client_up_to_date? = client_told&.except("when") == client_state.except("when")

  # After a change the client should hear about: their email goes out shortly, with the job's
  # other changes, unless staff chose not to tell them, in which case this is what they know.
  def tell_client(notify_client, visits = [ self ])
    if notify_client
      job.queue_client_notice!
    else
      visits.each { _1.update_columns(client_told: _1.client_state) }
    end
  end

  # The client's page for this visit (PLT-12): one link per visit, kept alive until a month
  # after the visit's day, wherever it moves.
  def client_link!
    expires_at = business.local_time(scheduled_on + 30, "23:59")
    link = ClientLink.active.where(linkable: self).order(:id).last
    return ClientLink.issue!(self, expires_at:) unless link

    link.update!(expires_at:) if link.expires_at && link.expires_at < expires_at
    link
  end

  def client_page_visible? = true
  def client_link_partial = "client/visits/visit"

  def snapshot
    { "when" => when_label(with_year: true), "on" => scheduled_on&.iso8601, "timing" => timing,
      "starts_at" => starts_at&.utc&.iso8601, "window_ends_at" => window_ends_at&.utc&.iso8601 }
  end

  def crew_names = assignees.map(&:full_name)

  # Called by schedule_all! for each visit it saves.
  def sync_assignments
    return if @assignee_ids.nil?

    current = assignments.map(&:user_id)
    assignments.where(user_id: current - @assignee_ids).delete_all
    (@assignee_ids - current).each { assignments.create!(user_id: _1) }
    assignments.reset
    assignees.reset
    @assignee_ids = nil
  end

  private

  # Every change takes the job's lock, then the visit's (the order Job#complete! uses, so the two
  # can't deadlock), checks the job is still open, and saves the change, its history and the
  # job's status together.
  def under_job_lock
    job.with_lock do
      raise NotOpen, "#{job.number} is #{job.status_label.downcase}. Reopen it to change its visits." unless job.open?

      yield
      job.refresh_status!
    end
    self
  end

  def clock(time) = time&.in_time_zone(business.time_zone)&.strftime("%H:%M")

  def clock_label(time, ampm: true)
    local = time.in_time_zone(business.time_zone)
    label = "#{(local.hour % 12).nonzero? || 12}#{":%02d" % local.min if local.min.positive?}"
    ampm ? "#{label} #{local.hour < 12 ? "am" : "pm"}" : label
  end

  # The form's wall-clock times on the visit's date, in the business's zone (so moving a visit to
  # another day keeps its clock time). A time that can't be read leaves none, and validation says so.
  def place_times
    return unless scheduled_on && business

    read = ->(value) { CLOCK.match?(value.to_s.strip) ? business.local_time(scheduled_on, value.to_s.strip.first(5)) : nil }
    self.starts_at = anytime? ? nil : read.(start_time)
    self.window_ends_at = window? ? read.(window_end_time) : nil
  end

  def times_make_sense
    case timing
    when "exact"
      errors.add(:start_time, "needs a time") unless starts_at
    when "window"
      errors.add(:start_time, "needs a time") unless starts_at
      errors.add(:window_end_time, "needs a time") unless window_ends_at
      errors.add(:window_end_time, "must be after the window starts") if starts_at && window_ends_at && window_ends_at <= starts_at
    end
  end

  # Active members, or someone already on this visit (kept even after they're deactivated).
  def assignees_are_members
    return if @assignee_ids.nil? || @assignee_ids.empty?

    allowed = business.business_users.active.where(user_id: @assignee_ids).pluck(:user_id) + (persisted? ? assignments.pluck(:user_id) : [])
    errors.add(:base, "Only people on your team can be assigned.") unless (@assignee_ids - allowed).empty?
  end
end
