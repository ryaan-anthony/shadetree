require "test_helper"

class LayoutHelperTest < ActionView::TestCase
  test "day period" do
    assert_equal "morning", day_period(Time.zone.parse("2026-01-01 08:00"))
    assert_equal "afternoon", day_period(Time.zone.parse("2026-01-01 13:00"))
    assert_equal "evening", day_period(Time.zone.parse("2026-01-01 19:00"))
  end

  test "the business mark's initials read on any brand color (QA #274)" do
    grey = Business.new(name: "Grey Co", brand_color: "#7b7b7b") # about 4.2:1 with white or ink
    branding = Branding.new(grey)
    assert_equal "background: #{branding.button_color}; color: #ffffff", business_mark_style(grey)
    assert_operator Branding.contrast(branding.button_color, "#ffffff"), :>=, 4.5
    assert_equal "background: #047857; color: #ffffff", business_mark_style(Business.new(name: "Oak", brand_color: "#047857"))
  end
end
