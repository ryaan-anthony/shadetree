# CAT-06: a day or days the business is closed (a holiday, vacation), all day or between two
# times on each of those days (a half day). A closure can repeat every year on the same month
# and day, from its first year on; the yearly ones can wrap the new year (Dec 24 to Jan 2).
class Closure < ApplicationRecord
  include BusinessOwned
  belongs_to_business_record :location, optional: true # CAT-07: none for the main location

  MAX = 200
  MAX_DAYS = 366
  END_OF_DAY = 24 * 60 # end_minute for "the rest of the day"

  normalizes :reason, with: ->(reason) { reason.to_s.squish }

  validates :reason, presence: true, length: { maximum: 60 }
  validates :starts_on, presence: true
  validate :dates_in_order
  validate :times_in_order
  validate :yearly_dates_exist, if: :repeats_yearly
  validate :within_limit, on: :create

  before_validation { self.ends_on ||= starts_on }
  before_validation { self.start_minute = self.end_minute = nil unless part_of_day } # all day: no times

  scope :ordered, -> { order(:starts_on, :start_minute, :id) }

  # Form fields: part of the day only, and its times as "HH:MM".
  attribute :part_of_day, :boolean
  after_initialize { self.part_of_day = !start_minute.nil? if part_of_day.nil? && has_attribute?(:start_minute) }

  def start_time = clock(start_minute)
  def end_time = (clock(end_minute) unless end_minute == END_OF_DAY)

  def start_time=(value)
    self.start_minute = minutes(value)
  end

  # Left empty, or midnight: closed for the rest of the day.
  def end_time=(value)
    minutes = value.to_s.strip.empty? ? END_OF_DAY : minutes(value)
    self.end_minute = minutes&.zero? ? END_OF_DAY : minutes
  end

  def all_day? = start_minute.nil?

  def covers?(date)
    return false if starts_on.nil? || date < starts_on
    return date <= ends_on unless repeats_yearly

    day = (date.month * 100) + date.day # 1225 for Dec 25
    from = (starts_on.month * 100) + starts_on.day
    to = (ends_on.month * 100) + ends_on.day
    from <= to ? day.between?(from, to) : (day >= from || day <= to)
  end

  # Whether it can still affect a day from `date` on.
  def current?(date) = repeats_yearly || ends_on >= date

  # The first day on or after `date` that it starts or is under way, for listing in order.
  def next_on(date)
    return [ starts_on, date ].max unless repeats_yearly
    return starts_on if date <= starts_on

    years = date.year - starts_on.year
    [ years - 1, years, years + 1 ].map { starts_on.next_year(_1) }.find { (_1 + (ends_on - starts_on)) >= date }
  end

  # The closed time on a covered date, in the business's zone (ends at the next midnight when
  # all day; a branch's zone for its closures, CAT-07). A wall-clock time a DST change skips moves ahead, as Business#local_time does.
  def period_on(date)
    place = location || business
    from = place.local_time(date, start_time || "00:00")
    to = end_time ? place.local_time(date, end_time) : place.local_time(date + 1, "00:00")
    from...to
  end

  # "Thu, Dec 25", "Mon, Dec 22 – Fri, Jan 2", with ", 12 pm–5 pm" for part of a day.
  def dates_label
    fmt = ->(date) { date.strftime(repeats_yearly ? "%b %-d" : "%a, %b %-d#{", %Y" if date.year != business.today.year}") }
    dates = ends_on == starts_on ? fmt.(starts_on) : "#{fmt.(starts_on)} – #{fmt.(ends_on)}"
    unless all_day?
      dates += end_time ? ", #{WeeklyHours.clock_label(start_time)}–#{WeeklyHours.clock_label(end_time)}" : ", from #{WeeklyHours.clock_label(start_time)}"
    end
    dates
  end

  private

  def clock(minutes) = minutes && format("%02d:%02d", *minutes.divmod(60))

  def minutes(value)
    value = WeeklyHours.normalize_clock(value)
    return nil unless WeeklyHours::CLOCK.match?(value)

    hour, minute = value.split(":").map { Integer(_1, 10) }
    (hour * 60) + minute
  end

  def dates_in_order
    return unless starts_on && ends_on

    if ends_on < starts_on then errors.add(:ends_on, "is before the first day")
    elsif ends_on - starts_on >= (repeats_yearly ? 365 : MAX_DAYS) then errors.add(:ends_on, "is more than a year after the first day")
    end
  end

  # Part of a day needs both times, on the same day (closures can't run past midnight).
  def times_in_order
    return unless part_of_day

    errors.add(:start_time, "needs a time") if start_minute.nil?
    errors.add(:end_time, "needs a time") if end_minute.nil?
    errors.add(:end_time, "is before the start. Closures can't run past midnight.") if start_minute && end_minute && end_minute <= start_minute
  end

  def yearly_dates_exist
    return unless [ starts_on, ends_on ].compact.any? { _1.month == 2 && _1.day == 29 }

    errors.add(:repeats_yearly, "can't start or end on February 29, which most years don't have")
  end

  def within_limit
    errors.add(:base, "A business can have up to #{MAX} closures. Remove past ones first.") if Closure.count >= MAX
  end
end
