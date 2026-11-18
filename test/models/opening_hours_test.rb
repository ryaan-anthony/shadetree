require "test_helper"

# CAT-06: weekly hours, closures and the "is the business open?" query they answer together.
class OpeningHoursTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
  end

  def closure(**attrs) = as_business(@business) { Closure.create!(reason: "Closed", **attrs) }
  def hours = OpeningHours.new(@business.reload)
  def at(date, clock) = @business.local_time(Date.parse(date), clock)

  test "weekly hours validate each day, and days can't run past midnight" do
    @business.weekly_hours = { "2" => { "opens" => "08:00", "closes" => "" }, "3" => { "opens" => "22:00", "closes" => "02:00" }, "4" => { "opens" => "9am", "closes" => "17:00" } }
    assert_not @business.valid?
    assert_equal [ "Tuesday needs a closing time.", "Wednesday closes before it opens. Hours that run past midnight aren't supported.", "Thursday needs an opening time." ],
                 @business.errors.full_messages_for(:weekly_hours)
    @business.weekly_hours = { "9" => {} }
    assert_not @business.valid?
  end

  test "the form keeps only the days marked open" do
    form = { "1" => { "open" => "1", "opens" => "09:00", "closes" => "17:30" }, "2" => { "opens" => "09:00", "closes" => "17:00" }, "6" => { "open" => "1", "opens" => " 10:00 ", "closes" => "14:00" } }
    assert_equal({ "1" => { "opens" => "09:00", "closes" => "17:30" }, "6" => { "opens" => "10:00", "closes" => "14:00" } }, WeeklyHours.from_form(form))
    assert_equal({}, WeeklyHours.from_form({}), "closed every day is still set")
  end

  test "a summary groups days with the same hours" do
    @business.weekly_hours = WeeklyHours::WEEKDAYS_8_TO_5.merge("6" => { "opens" => "09:30", "closes" => "13:00" })
    assert_equal [ "Mon–Fri 8 am–5 pm", "Sat 9:30 am–1 pm" ], @business.hours.summary
    assert_equal [], Business.new.hours.summary
  end

  test "open at a time and on a date, in the business's time zone" do
    assert hours.open_at?(at("2026-11-18", "08:00")) # a Wednesday
    assert_not hours.open_at?(at("2026-11-18", "17:00")), "closing time itself is closed"
    assert_not hours.open_at?(at("2026-11-18", "07:59"))
    assert hours.open_at?(Time.utc(2026, 11, 18, 21, 59)), "4:59 pm in New York"
    assert_not hours.open_at?(Time.utc(2026, 11, 18, 22, 0))
    assert hours.open_on?(Date.new(2026, 11, 20))
    assert_not hours.open_on?(Date.new(2026, 11, 21)), "Saturday"
  end

  test "until hours are set, every day is open (closures still apply)" do
    @business.update!(weekly_hours: nil)
    assert_not hours.set?
    assert hours.open_at?(at("2026-11-21", "23:30"))
    closure(starts_on: Date.new(2026, 11, 21))
    assert_not hours.open_on?(Date.new(2026, 11, 21))
  end

  test "closures: all day, a range, and part of each day" do
    closure(reason: "Vacation", starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 3))
    closure(reason: "Half day", starts_on: Date.new(2026, 12, 24), part_of_day: true, start_time: "12:00", end_time: "17:00")
    h = hours
    assert_not h.open_on?(Date.new(2026, 12, 2))
    assert h.open_on?(Date.new(2026, 12, 4))
    assert h.open_at?(at("2026-12-24", "11:59"))
    assert_not h.open_at?(at("2026-12-24", "12:00"))
    day = h.day(Date.new(2026, 12, 24))
    assert_equal [ "Half day" ], day.closures.map(&:reason)
    assert_not day.closed_all_day?
    assert_equal [ at("2026-12-24", "08:00")...at("2026-12-24", "12:00") ], day.periods
  end

  test "a part-day closure with no end runs to midnight" do
    early = closure(reason: "Closing early", starts_on: Date.new(2026, 12, 31), part_of_day: true, start_time: "13:00", end_time: "")
    assert_equal Closure::END_OF_DAY, early.end_minute
    assert_nil early.end_time
    assert_equal "Thu, Dec 31, from 1 pm", early.dates_label
    assert_equal at("2027-01-01", "00:00"), early.period_on(Date.new(2026, 12, 31)).end
  end

  test "a closure in the middle of the day splits it" do
    closure(starts_on: Date.new(2026, 11, 18), part_of_day: true, start_time: "12:00", end_time: "13:00")
    assert_equal [ at("2026-11-18", "08:00")...at("2026-11-18", "12:00"), at("2026-11-18", "13:00")...at("2026-11-18", "17:00") ],
                 hours.day(Date.new(2026, 11, 18)).periods
  end

  test "yearly closures repeat from their first year, including across the new year" do
    closure(reason: "Christmas", starts_on: Date.new(2026, 12, 25), repeats_yearly: true)
    closure(reason: "Winter break", starts_on: Date.new(2026, 12, 30), ends_on: Date.new(2027, 1, 2), repeats_yearly: true)
    h = hours
    assert_not h.open_on?(Date.new(2030, 12, 25))
    assert h.open_on?(Date.new(2025, 12, 25)), "not before it was added"
    assert_not h.open_on?(Date.new(2031, 1, 2)), "Thursday Jan 2, inside the wrapped range"
    assert h.open_on?(Date.new(2031, 1, 3))
  end

  test "hours and closures keep to local clock time across DST" do
    # Sunday Mar 8, 2026: New York skips 2:00–3:00. Hours of 1:00–4:00 that day are 2 hours long.
    @business.update!(weekly_hours: { "0" => { "opens" => "01:00", "closes" => "04:00" }, "1" => { "opens" => "08:00", "closes" => "17:00" } })
    period = hours.day(Date.new(2026, 3, 8)).periods.sole
    assert_equal 2.hours, period.end - period.begin
    assert_equal Time.utc(2026, 3, 9, 12), hours.day(Date.new(2026, 3, 9)).periods.sole.begin, "8 am EDT is 12:00 UTC"
    assert_equal Time.utc(2026, 3, 2, 13), hours.day(Date.new(2026, 3, 2)).periods.sole.begin, "8 am EST is 13:00 UTC"
    # Nov 1, 2026 repeats 1:00–2:00: an all-day closure still covers the whole 25-hour day.
    closure(starts_on: Date.new(2026, 11, 1))
    covered = as_business(@business) { Closure.last }.period_on(Date.new(2026, 11, 1))
    assert_equal 25.hours, covered.end - covered.begin
  end

  test "closure validation" do
    as_business(@business) do
      assert_not Closure.new(reason: "", starts_on: Date.new(2026, 1, 1)).valid?
      backwards = Closure.new(reason: "x", starts_on: Date.new(2026, 1, 5), ends_on: Date.new(2026, 1, 1))
      assert_equal [ "Last day is before the first day" ], backwards.tap(&:validate).errors.full_messages
      assert_not Closure.new(reason: "x", starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2027, 1, 5)).valid?
      overnight = Closure.new(reason: "x", starts_on: Date.new(2026, 1, 1), part_of_day: true, start_time: "20:00", end_time: "02:00")
      assert_includes overnight.tap(&:validate).errors.full_messages, "Until is before the start. Closures can't run past midnight."
      leap = Closure.new(reason: "x", starts_on: Date.new(2028, 2, 29), repeats_yearly: true)
      assert_includes leap.tap(&:validate).errors.full_messages, "can't start or end on February 29, which most years don't have"
      whole_day = Closure.create!(reason: "x", starts_on: Date.new(2026, 1, 1), part_of_day: false, start_time: "09:00", end_time: "10:00")
      assert whole_day.all_day?, "times are dropped when it's all day"
    end
  end

  test "closures belong to one business" do
    closure(starts_on: Date.new(2026, 11, 18))
    other = businesses(:two)
    assert_equal 0, as_business(other) { Closure.count }
    assert OpeningHours.new(other).open_on?(Date.new(2026, 11, 18))
  end
end
