require "test_helper"

class LayoutHelperTest < ActionView::TestCase
  test "brand colour falls back to canopy when missing or malformed" do
    assert_equal "#047857", brand_color(nil)
    assert_equal "#047857", brand_color(Business.new(brand_color: "red; background: url(x)"))
    assert_equal "#9a3412", brand_color(Business.new(brand_color: "#9A3412"))
  end

  test "readable ink picks the higher-contrast text colour" do
    assert_equal "#ffffff", readable_ink("#9a3412")
    assert_equal "#ffffff", readable_ink("#047857")
    assert_equal "#0f172a", readable_ink("#facc15")
    assert_equal "#0f172a", readable_ink("#ffffff")
  end

  test "client brand style only emits validated values" do
    style = client_brand_style(Business.new(brand_color: "#facc15"))
    assert_includes style, "--color-brand: #facc15"
    assert_includes style, "--color-brand-ink: #0f172a"
  end

  test "day period" do
    assert_equal "morning", day_period(Time.zone.parse("2026-01-01 08:00"))
    assert_equal "afternoon", day_period(Time.zone.parse("2026-01-01 13:00"))
    assert_equal "evening", day_period(Time.zone.parse("2026-01-01 19:00"))
  end
end
