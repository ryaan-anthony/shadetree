require "test_helper"

class BusinessTimeTest < ActiveSupport::TestCase
  setup { @business = Business.new(name: "Oakline", timezone: "America/New_York") }

  test "time zone falls back to UTC and accepts IANA and Rails names" do
    assert_equal "America/New_York", @business.time_zone.tzinfo.identifier
    assert_equal "UTC", Business.new.time_zone.name
    assert Business.new(name: "x", timezone: "Eastern Time (US & Canada)").tap(&:validate).errors[:timezone].empty?
    assert_includes Business.new(name: "x", timezone: "Mars/Olympus").tap(&:validate).errors[:timezone], "is not a time zone we recognise"
  end

  test "today is the business's date, not the server's" do
    travel_to Time.utc(2026, 11, 14, 3, 30) do # 22:30 on Nov 13 in New York
      assert_equal Date.new(2026, 11, 13), @business.today
      assert_equal Date.new(2026, 11, 14), Date.current
    end
  end

  test "wall-clock times convert to the right UTC instant across DST" do
    assert_equal Time.utc(2026, 3, 7, 14), @business.local_time(Date.new(2026, 3, 7), "09:00") # EST, UTC-5
    assert_equal Time.utc(2026, 3, 9, 13), @business.local_time(Date.new(2026, 3, 9), "09:00") # EDT, UTC-4
  end

  test "a weekly 9:00 visit stays at 9:00 local through both DST changes" do
    first = @business.local_time(Date.new(2026, 2, 26), "09:00")
    visits = Array.new(40) { |week| first + week.weeks }
    assert visits.all? { |visit| visit.hour == 9 && visit.min.zero? }
    assert_equal [ -5, -4 ], visits.map { _1.utc_offset / 3600 }.uniq.first(2)
  end

  test "a time skipped by spring-forward moves ahead; a repeated one takes the first occurrence" do
    skipped = @business.local_time(Date.new(2026, 3, 8), "02:30")
    assert_equal [ 3, 30 ], [ skipped.hour, skipped.min ]
    repeated = @business.local_time(Date.new(2026, 11, 1), "01:30")
    assert_equal Time.utc(2026, 11, 1, 5, 30), repeated # 01:30 EDT, the first one
  end

  test "durations across DST count real hours" do
    start = @business.local_time(Date.new(2026, 3, 7), "22:00")
    finish = @business.local_time(Date.new(2026, 3, 8), "06:00")
    assert_equal 7.hours, finish - start
  end

  test "date-only values are never shifted by zone" do
    due = Date.new(2026, 12, 1)
    @business.use_time_zone { assert_equal due, due.in_time_zone.to_date }
    Time.use_zone("Pacific/Honolulu") { assert_equal due, due.in_time_zone.to_date }
  end

  test "use_time_zone scopes Time.zone to the business" do
    @business.use_time_zone { assert_equal "America/New_York", Time.zone.tzinfo.identifier }
    assert_equal "UTC", Time.zone.name
  end

  test "money helper uses the business currency" do
    assert_equal Money.new(1250, "USD"), @business.money("12.50")
    assert_equal "GBP", Business.new(currency: "GBP").money("1").currency
  end
end
