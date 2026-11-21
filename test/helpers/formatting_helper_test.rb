require "test_helper"

class FormattingHelperTest < ActionView::TestCase
  test "money formats or stays blank" do
    assert_equal "$12.50", money(Money.new(1250, "USD"))
    assert_equal "No charge", money(Money.zero("USD"), zero: "No charge")
    assert_nil money(nil)
  end

  test "local_time shows the zone's wall clock and keeps the UTC instant" do
    instant = Time.utc(2026, 3, 9, 13)
    html = Time.use_zone("America/New_York") { local_time(instant) }
    assert_dom_equal '<time datetime="2026-03-09T13:00:00Z">Mar 9, 2026, 9:00 AM</time>', html
    assert_includes local_time(instant, format: :time, zone: "America/Los_Angeles"), "6:00 AM"
    assert_nil local_time(nil)
  end

  test "local_date never shifts" do
    html = Time.use_zone("Pacific/Kiritimati") { local_date(Date.new(2026, 12, 1)) }
    assert_dom_equal '<time datetime="2026-12-01">Dec 1, 2026</time>', html
  end

  test "dates leave off this year's year where asked, never on today's pages, and keep it otherwise (PLT-05)" do
    travel_to Time.zone.local(2026, 11, 20, 12) do
      assert_dom_equal '<time datetime="2026-11-20">Friday, November 20</time>', friendly_date(Date.new(2026, 11, 20))
      assert_dom_equal '<time datetime="2027-01-04">Mon, Jan 4, 2027</time>', friendly_date(Date.new(2027, 1, 4), format: :weekday)
      assert_includes friendly_date(Date.new(2027, 1, 4), year: false), ">Monday, January 4<"
      assert_includes friendly_date(Date.new(2026, 11, 20), year: true), "November 20, 2026"
      assert_includes local_date(Date.new(2026, 12, 1)), "Dec 1, 2026", "records keep the year by default"
      assert_includes local_date(Date.new(2026, 12, 1), year: :auto), ">Dec 1<"
      assert_includes local_time(Time.utc(2026, 3, 9, 13), zone: "America/New_York", year: :auto), ">Mar 9, 9:00 AM<"
      assert_includes local_time(Time.utc(2025, 3, 9, 13), zone: "America/New_York", year: :auto), "Mar 9, 2025"
    end
  end

  test "zones are named as Settings names them" do
    assert_equal "Eastern Time (US & Canada)", time_zone_label("America/New_York")
    assert_equal "Pacific Time (US & Canada)", time_zone_label(ActiveSupport::TimeZone["America/Los_Angeles"])
  end
end
