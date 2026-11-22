# When something booked on one day happens (JOB-02 visits, CLI-07 request follow-ups): at a
# start time, in an arrival window ("arrive 8–10") or anytime that day, for an estimated
# duration. Times are entered as wall-clock times ("09:00") in the place's zone and stored in
# UTC on the record's own date there. The including class says where it is with #place (the
# business, or a location with its own time zone, CAT-07).
#
# Needs scheduled_on, timing, starts_at, window_ends_at and duration_minutes columns.
module ArrivalTiming
  extend ActiveSupport::Concern

  TIMINGS = %w[exact window anytime].freeze
  MAX_DURATION = 24 * 60
  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d(:00)?\z/ # "HH:MM" from a time field (browsers may add ":00")

  included do
    validates :scheduled_on, presence: true
    validates :timing, inclusion: { in: TIMINGS }
    validates :duration_minutes, numericality: { only_integer: true, in: 5..MAX_DURATION, message: "must be between 5 minutes and 24 hours" }
    validate :times_make_sense

    before_validation :place_times

    # Form fields: wall-clock times ("09:00").
    attr_writer :start_time, :window_end_time
  end

  def start_time = @start_time || clock(starts_at)
  def window_end_time = @window_end_time || clock(window_ends_at)

  # The duration in hours ("1.5"), as the forms show and take it.
  def duration_hours = (duration_minutes.to_d / 60).round(2).to_s("F").sub(/\.0\z/, "")

  def duration_hours=(value)
    hours = BigDecimal(value.to_s.strip, exception: false)
    self.duration_minutes = hours && (hours * 60).round
  end

  # The form's values (times) aren't columns, so a reload forgets them too; otherwise a
  # reloaded record would still show the times it was first given.
  def reload(...)
    @start_time = @window_end_time = nil
    super
  end

  # JOB-03: the time attributes for a move to `at` ("HH:MM", a window keeps its length), or the
  # current times when there's no new start (or it's anytime).
  def moved_time_attributes(at)
    return { start_time:, window_end_time: } unless at && !anytime?
    raise ArgumentError, "Choose a time like 09:30." unless CLOCK.match?(at)

    length = window? ? ((window_ends_at - starts_at) / 60).round : 0
    start = (at[0, 2].to_i * 60) + at[3, 2].to_i
    raise ArgumentError, "That window would run past midnight." if start + length >= 24 * 60

    { start_time: at.first(5), window_end_time: (format("%02d:%02d", *(start + length).divmod(60)) if window?) }.compact
  end

  def anytime? = timing == "anytime"
  def window? = timing == "window"

  # When it's expected to finish: the start (or the window's end) plus the duration.
  def ends_at = starts_at && ((window_ends_at || starts_at) + duration_minutes.minutes)

  # "9 am", "Arrive 8–10 am", "Anytime".
  def time_label
    case timing
    when "exact" then clock_label(starts_at)
    when "window"
      same_half = starts_at.in_time_zone(place.time_zone).hour < 12 == window_ends_at.in_time_zone(place.time_zone).hour < 12
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

  # When it is, as shown ("when") and as values, for histories.
  def snapshot
    { "when" => when_label(with_year: true), "on" => scheduled_on&.iso8601, "timing" => timing,
      "starts_at" => starts_at&.utc&.iso8601, "window_ends_at" => window_ends_at&.utc&.iso8601 }
  end

  # Its own time zone, and its start on another clock (the calendar's, CAT-07).
  def time_zone = place.time_zone
  def start_time_in(zone) = starts_at&.in_time_zone(zone)&.strftime("%H:%M")

  private

  def clock(time) = time&.in_time_zone(place.time_zone)&.strftime("%H:%M")

  def clock_label(time, ampm: true)
    local = time.in_time_zone(place.time_zone)
    label = "#{(local.hour % 12).nonzero? || 12}#{":%02d" % local.min if local.min.positive?}"
    ampm ? "#{label} #{local.hour < 12 ? "am" : "pm"}" : label
  end

  # The form's wall-clock times on the record's date, in the place's zone (so moving it to
  # another day keeps its clock time). A time that can't be read leaves none, and validation says so.
  def place_times
    return unless scheduled_on && business

    read = ->(value) { CLOCK.match?(value.to_s.strip) ? place.local_time(scheduled_on, value.to_s.strip.first(5)) : nil }
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
end
