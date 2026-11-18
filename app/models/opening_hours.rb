# CAT-06: when a business is open, for scheduling (JOB-02 warnings, JOB-03 shading) and later
# self-booking. Combines the weekly hours with closures, in the business's time zone:
#
#   hours = OpeningHours.new(business)
#   hours.open_at?(visit.starts_at)   # inside the day's hours and not closed then
#   hours.open_on?(date)              # open at some point that day
#   hours.day(date)                   # its open periods, hours and closures, for a calendar
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
    closures = closures_on(date)
    hours = @weekly.set? ? @weekly.for(date.wday) : nil
    periods = if !@weekly.set? then [ @business.local_time(date, "00:00")...@business.local_time(date + 1, "00:00") ]
    elsif hours then [ @business.local_time(date, hours[0])...@business.local_time(date, hours[1]) ]
    else []
    end
    closures.each { |closure| periods = periods.flat_map { subtract(_1, closure.period_on(date)) } }
    Day.new(date:, hours:, closures:, periods: periods.reject { _1.begin >= _1.end })
  end

  def closures_on(date) = all_closures.select { _1.covers?(date) }

  private

  def all_closures
    @all_closures ||= Tenancy.with_business(@business) { Closure.ordered.to_a }.each { _1.association(:business).target = @business } # no query per closure
  end

  # An open period with a closed one taken out: zero, one or two periods.
  def subtract(open, closed)
    return [ open ] if closed.end <= open.begin || closed.begin >= open.end

    [ (open.begin...closed.begin if closed.begin > open.begin), (closed.end...open.end if closed.end < open.end) ].compact
  end
end
