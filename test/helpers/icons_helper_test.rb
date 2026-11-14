require "test_helper"

class IconsHelperTest < ActionView::TestCase
  test "renders a decorative inline svg by default" do
    html = icon("calendar")
    assert_includes html, "<svg"
    assert_includes html, 'aria-hidden="true"'
    assert_includes html, 'class="size-4"'
    assert_includes html, "<rect"
  end

  test "a label makes the icon an image with an accessible name" do
    html = icon("trash", label: "Delete", class: "size-5")
    assert_includes html, 'role="img"'
    assert_includes html, 'aria-label="Delete"'
    assert_includes html, "<title>Delete</title>"
    assert_not_includes html, "aria-hidden"
  end

  test "domain aliases and custom glyphs resolve" do
    assert IconsHelper.known?("quote")
    assert IconsHelper.known?("invoice")
    assert_includes icon("job"), "<rect" # briefcase
  end

  test "unknown names raise so typos fail loudly in tests" do
    assert_raises(IconsHelper::UnknownIcon) { icon("calculator") }
  end
end
