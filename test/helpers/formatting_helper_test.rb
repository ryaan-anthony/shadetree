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

  test "phone numbers: North American ones formatted and dialled with +1, others as typed (QA #274)" do
    assert_equal "(215) 555-1212", phone_number("2155551212")
    assert_equal "(215) 555-1212", phone_number("+1 215.555.1212")
    assert_equal "tel:+12155551212", phone_href("1 (215) 555-1212")
    assert_equal "+44 20 7946 0958", phone_number("+44 20 7946 0958")
    assert_equal "tel:+442079460958", phone_href("+44 20 7946 0958")
    assert_equal "215-555-1212 x12", phone_number("215-555-1212 x12")
    assert_equal "tel:+12155551212", phone_href("215-555-1212 x12"), "the extension isn't dialled"
    assert_dom_equal '<a class="x" href="tel:+12155551212">(215) 555-1212</a>', phone_link("2155551212", class: "x")
    assert_nil phone_link("")
    assert_nil phone_number(nil)
  end
end
