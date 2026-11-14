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
end
