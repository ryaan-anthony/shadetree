require "test_helper"

class InlineStyleHelperTest < ActionView::TestCase
  def content_security_policy_nonce = "abc123"

  test "declarations become a shared class backed by one nonced block" do
    first = inline_style("top: 64px; height: 32px")
    assert_equal first, inline_style("top: 64px; height: 32px")
    other = inline_style("top: 0px")
    tag = inline_styles_tag
    assert_includes tag, %(nonce="abc123")
    assert_includes tag, ".#{first}{top: 64px; height: 32px}"
    assert_includes tag, ".#{other}{top: 0px}"
    assert_nil inline_styles_tag, "rules aren't emitted twice"
    later = inline_style("left: 2px")
    assert_equal ".#{later}{left: 2px}", Nokogiri::HTML.fragment(inline_styles_tag).at_css("style").text
  end

  test "markup and rules can't get in" do
    [ "color: red}</style><script>x()</script>", "a{b}", "background: url(x) /* */", "content: '\\3c'" ].each do |css|
      assert_raises(ArgumentError) { inline_style(css) }
    end
    assert_raises(ArgumentError) { inline_style_rule("body{", "color: red") }
    assert_equal %(<style nonce="abc123">body.client{color: red}</style>), inline_style_rule("body.client", "color: red")
  end
end
