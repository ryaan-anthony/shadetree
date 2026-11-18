# CAT-06: when a business is open, for scheduling (JOB-02 warnings, JOB-03 shading) and later
# self-booking. Combines the weekly hours with closures, in the business's time zone:
#
#   hours = OpeningHours.new(business)
#   hours.open_at?(visit.starts_at)   # inside the day's hours and not closed then
#   hours.open_on?(date)              # open at some point that day
#   hours.day(date)                   # its open periods, hours and closures, for a calendar
#   hours.problems(date, from, to)    # why work then would be outside hours, for warnings (JOB-02)
#
# Until the weekly hours are set, every day counts as open all day (closures still apply), so
# nothing is shaded or warned about. Closures are read once per instance: make one per request.
class OpeningHours
  Day = Data.define(:date, :hours, :closures, :periods) do
    def open? = periods.any?
    def closed_all_day? = closures.any?(&:all_day?)
  end

  def initialize(business)
    @business = business
    @weekly = business.hours
  end

  def set? = @weekly.set?

  def open_at?(time)
    local = time.in_time_zone(@business.time_zone)
    day(local.to_date).periods.any? { _1.cover?(local) }
  end

  def open_on?(date) = day(date).open?

  def day(date)
    date = date.to_date
    (@days ||= {})[date] ||= build_day(date) # a calendar asks about the same days many times
  end

  def closures_on(date) = all_closures.select { _1.covers?(date) }

  Problem = Data.define(:kind, :message)

  # JOB-02: why work on `date` from `from` to `to` (TimeWithZone, or nil for "anytime that day")
  # wouldn't fit the business's hours: a closure it touches, a day the business is closed, or
  # time outside the day's hours. Empty when it fits, and when hours aren't set (except closures).
  def problems(date, from = nil, to = nil)
    day = day(date)
    found = []
    clashing = day.closures.select { |closure| from.nil? || closure.all_day? || overlaps?(closure.period_on(day.date), from...to) }
    clashing.each do |closure|
      found << Problem.new(:closure, "#{closure.all_day? ? "You're closed" : "You're closed #{closure_hours(closure)}"} for #{closure.reason}.")
    end
    return found if clashing.any? || !set? # a closure says enough on its own

    if day.hours.nil?
      found << Problem.new(:closed_day, "You're closed on #{date.strftime("%A")}s.")
    elsif from && !day.periods.any? { _1.begin <= from && to <= _1.end }
      found << Problem.new(:outside_hours, "That's outside your hours (#{WeeklyHours.clock_label(day.hours[0])}–#{WeeklyHours.end_of_day?(day.hours[1]) ? "midnight" : WeeklyHours.clock_label(day.hours[1])}).")
    end
    found
  end

  private

  def build_day(date)
    closures = closures_on(date)
    hours = @weekly.set? ? @weekly.for(date.wday) : nil
    periods = if !@weekly.set? then [ @business.local_time(date, "00:00")...@business.local_time(date + 1, "00:00") ]
    elsif hours then [ @business.local_time(date, hours[0])...@business.local_time(WeeklyHours.end_of_day?(hours[1]) ? date + 1 : date, hours[1]) ]
    else []
    end
    closures.each { |closure| periods = periods.flat_map { subtract(_1, closure.period_on(date)) } }
    Day.new(date:, hours:, closures:, periods: periods.reject { _1.begin >= _1.end })
  end

  def all_closures
    # Through the association, so even inside Tenancy.across_businesses only this business's
    # closures load; the business is set on each so none queries for it.
    @all_closures ||= Tenancy.with_business(@business) { @business.closures.ordered.to_a }.each { _1.association(:business).target = @business }
  end

  def overlaps?(a, b) = a.begin < b.end && b.begin < a.end

  def closure_hours(closure)
    closure.end_time ? "#{WeeklyHours.clock_label(closure.start_time)}–#{WeeklyHours.clock_label(closure.end_time)}" : "from #{WeeklyHours.clock_label(closure.start_time)}"
  end

  # An open period with a closed one taken out: zero, one or two periods.
  def subtract(open, closed)
    return [ open ] if closed.end <= open.begin || closed.begin >= open.end

    [ (open.begin...closed.begin if closed.begin > open.begin), (closed.end...open.end if closed.end < open.end) ].compact
  end
end
