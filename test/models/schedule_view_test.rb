require "test_helper"

# JOB-03: where visits sit on the calendar's grid.
class ScheduleViewTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    Current.business = @business
    client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
    @job = Job.create!(client:, title: "Spring cleanup")
  end

  teardown { Current.reset }

  def book(on, at, minutes, timing: "exact") = @job.visits.new(scheduled_on: on, timing:, start_time: at, duration_minutes: minutes).tap { _1.schedule!(by: @owner) }

  def view(date, **) = ScheduleView.new(@business, view: "day", date:, **)

  test "the grid is the business's hours, stretched to fit a visit outside them" do
    monday = Date.new(2026, 11, 23)
    assert_equal 8...17, view(monday).hours
    book(monday, "06:30", 60)
    book(monday, "17:00", 90)
    assert_equal 6...19, view(monday).hours
    @business.update!(weekly_hours: {})
    assert_equal ScheduleView::DEFAULT_HOURS.first...ScheduleView::DEFAULT_HOURS.last, view(monday + 7).hours, "no hours set: 7 am to 7 pm"
  end

  test "a closure at the start of a day is shaded, not cut off the grid" do
    monday = Date.new(2026, 11, 23)
    Closure.create!(reason: "Staff meeting", starts_on: monday, start_time: "08:00", end_time: "12:00")
    schedule = view(monday)
    assert_equal 8...17, schedule.hours
    assert_equal [ [ 0, 4 * ScheduleView::HOUR_PX ] ], schedule.shades_on(monday).map { [ _1.top, _1.height ] }
  end

  test "short visits one after another, drawn taller than they last, sit side by side" do
    monday = Date.new(2026, 11, 23)
    first, second = book(monday, "09:00", 10), book(monday, "09:10", 10)
    placed = view(monday).placed_in(ScheduleView::Column.new(monday, nil)).index_by(&:visit)
    assert_equal [ 0, 1 ], [ first, second ].map { placed[_1].column }
  end

  test "visits are placed by time; overlapping ones share the width side by side" do
    monday = Date.new(2026, 11, 23)
    a = book(monday, "09:00", 120)
    b = book(monday, "10:00", 60)
    c = book(monday, "11:00", 60)
    d = book(monday, "13:00", 15)
    placed = view(monday).placed_in(ScheduleView::Column.new(monday, nil)).index_by(&:visit)
    hour = ScheduleView::HOUR_PX
    assert_equal [ hour, 2 * hour ], placed[a].to_h.values_at(:top, :height), "9 am is an hour below 8 am"
    assert_equal [ 0, 1, 0 ], [ a, b, c ].map { placed[_1].column }, "11:00 goes under 9:00 once that's done"
    assert_equal [ 2, 2, 1 ], [ a, b, c ].map { placed[_1].columns }, "11:00 overlaps nothing, so it has the full width"
    assert_equal [ 0, 1, 22 ], placed[d].to_h.values_at(:column, :columns, :height), "on its own, and tall enough to read"
  end

  test "a day when the clocks change still lines visits up with the hour labels" do
    sunday = Date.new(2026, 11, 1) # clocks go back at 2 am
    book(sunday, "10:00", 60)
    schedule = ScheduleView.new(@business, view: "day", date: sunday)
    assert_equal (10 - schedule.hours.first) * ScheduleView::HOUR_PX, schedule.placed_in(ScheduleView::Column.new(sunday, nil)).sole.top
  end

  test "closed time is shaded: before opening, after closing and closures" do
    saturday = Date.new(2026, 11, 28)
    week = ScheduleView.new(@business, date: saturday)
    assert_equal [ [ 0, 9 * ScheduleView::HOUR_PX ] ], week.shades_on(saturday).map { [ _1.top, _1.height ] }, "closed all day"
    Closure.create!(reason: "Staff training", starts_on: saturday - 2, start_time: "13:00", end_time: "17:00")
    assert_equal [ [ 5 * ScheduleView::HOUR_PX, 4 * ScheduleView::HOUR_PX ] ], ScheduleView.new(@business, date: saturday).shades_on(saturday - 2).map { [ _1.top, _1.height ] }
    assert_empty week.shades_on(saturday - 3)
  end

  test "booked hours count each person on a visit, whatever the filter" do
    monday = Date.new(2026, 11, 23)
    tech = User.create!(email: "t@example.com", password: "password123", first_name: "Tia", confirmed_at: Time.current)
    BusinessUser.create!(user: tech, business: @business, role: "technician")
    @job.visits.new(scheduled_on: monday, timing: "anytime", duration_minutes: 90, assignee_ids: [ tech.id, @owner.id ]).schedule!(by: @owner)
    schedule = ScheduleView.new(@business, date: monday, member: "unassigned")
    assert_equal({ tech.id => 1.5, @owner.id => 1.5 }, schedule.booked_hours)
    assert_empty schedule.visits
  end
end
