require "test_helper"

class LayoutHelperTest < ActionView::TestCase
  test "client brand style comes from Branding" do
    assert_equal Branding.new(businesses(:one)).css_variables, client_brand_style(businesses(:one))
  end

  test "day period" do
    assert_equal "morning", day_period(Time.zone.parse("2026-01-01 08:00"))
    assert_equal "afternoon", day_period(Time.zone.parse("2026-01-01 13:00"))
    assert_equal "evening", day_period(Time.zone.parse("2026-01-01 19:00"))
  end
end
