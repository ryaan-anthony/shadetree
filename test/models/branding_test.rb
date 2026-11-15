require "test_helper"

# CAT-02: the single source of client-facing branding.
class BrandingTest < ActiveSupport::TestCase
  def branding(**attributes) = Branding.new(Business.new(name: "Oakline Lawn & Landscape", **attributes))

  test "color falls back to the default when missing or malformed, so nothing unsafe reaches CSS" do
    assert_equal "#047857", Branding.new(nil).color
    assert_equal "#047857", branding(brand_color: "red; background: url(x)").color
    assert_equal "#9a3412", branding(brand_color: "#9A3412").color
    css = branding(brand_color: "#facc15").css_variables
    assert_includes css, "--color-brand: #facc15"
    assert_includes css, "--color-brand-ink: #0f172a"
  end

  test "text on the brand color is white or ink, whichever reads better" do
    assert_equal "#ffffff", branding(brand_color: "#9a3412").ink
    assert_equal "#ffffff", branding(brand_color: "#047857").ink
    assert_equal "#0f172a", branding(brand_color: "#facc15").ink
    assert_equal "#0f172a", branding(brand_color: "#ffffff").ink
  end

  test "contrast warnings follow WCAG thresholds" do
    assert_empty branding(brand_color: "#047857").contrast_warnings
    assert_empty branding(brand_color: "#9a3412").contrast_warnings
    light = branding(brand_color: "#facc15").contrast_warnings
    assert_equal 1, light.size, "ink text reads on yellow, but yellow is faint on white"
    assert_match "light against a white page", light.first
    mid = branding(brand_color: "#7b7b7b").contrast_warnings # about 4.2:1 against both white and ink
    assert_match "Button text may be hard to read", mid.first
    assert_in_delta 21.0, Branding.contrast("#000000", "#ffffff"), 0.01
    Branding::PRESETS.each_value { assert_empty branding(brand_color: _1).contrast_warnings, _1 }
  end

  test "without a logo there's a name-based wordmark" do
    plain = branding
    assert_not plain.logo?
    assert_nil plain.logo(:pdf)
    assert_equal "OL", plain.initials
    assert_equal "Oakline Lawn & Landscape", plain.name
  end

  test "Powered by Shadetree shows until a plan removes it" do
    assert branding.show_powered_by?
  end
end
