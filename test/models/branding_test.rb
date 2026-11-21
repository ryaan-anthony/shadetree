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
    assert_match "buttons use a slightly darker shade", mid.first
    assert_in_delta 21.0, Branding.contrast("#000000", "#ffffff"), 0.01
    Branding::PRESETS.each_value { assert_empty branding(brand_color: _1).contrast_warnings, _1 }
  end

  # Owner, 2026-11-21: link text (and button backgrounds where no text color reads) are the brand
  # darkened, same hue, just enough for 4.5:1; colors that already pass are unchanged.
  test "link text is darkened to 4.5:1 on the client page, keeping the hue" do
    green = branding(brand_color: "#059669") # the Shadetree green: 3.77:1 on white
    assert_equal "#048059", green.link_color
    assert_operator Branding.contrast(green.link_color, Branding::CLIENT_PAGE), :>=, 4.5
    assert_operator Branding.contrast(green.link_color, Branding::WHITE), :>=, 4.5

    yellow = branding(brand_color: "#fef08a") # very light
    assert_operator Branding.contrast(yellow.link_color, Branding::CLIENT_PAGE), :>=, 4.5
    assert_equal hue("#fef08a"), hue(yellow.link_color)

    assert_equal "#0b1221", branding(brand_color: "#0b1221").link_color, "a dark navy already passes"
    assert_equal "#047857", branding(brand_color: "#047857").link_color, "so does the default"
    Branding::PRESETS.each_value { assert_equal _1, branding(brand_color: _1).link_color, _1 }
  end

  test "buttons keep the brand unless no text reads on it, then darken it for white text" do
    assert_equal [ "#047857", "#ffffff" ], branding(brand_color: "#047857").then { [ _1.button_color, _1.button_ink ] }
    assert_equal [ "#facc15", "#0f172a" ], branding(brand_color: "#facc15").then { [ _1.button_color, _1.button_ink ] }, "ink reads on yellow"
    grey = branding(brand_color: "#7b7b7b") # about 4.2:1 against both white and ink
    assert_equal "#ffffff", grey.button_ink
    assert_operator Branding.contrast(grey.button_color, "#ffffff"), :>=, 4.5
    assert_equal "#7b7b7b", grey.color, "the chosen color is kept for accents"
    css = grey.css_variables
    assert_includes css, "--color-brand: #7b7b7b"
    assert_includes css, "--color-brand-button: #{grey.button_color}"
    assert_includes css, "--color-brand-link: #{grey.link_color}"
  end

  def hue(hex)
    r, g, b = hex.delete("#").scan(/../).map { _1.to_i(16) / 255.0 }
    max, min = [ r, g, b ].max, [ r, g, b ].min
    return 0 if max == min

    degrees = case max
    when r then 60 * (((g - b) / (max - min)) % 6)
    when g then 60 * (((b - r) / (max - min)) + 2)
    else 60 * (((r - g) / (max - min)) + 4)
    end
    degrees.round
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
