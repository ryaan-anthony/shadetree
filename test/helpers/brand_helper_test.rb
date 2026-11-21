require "test_helper"

# The Shadetree wordmark (owner decision 2026-11-21, MKT-01): "Shade" green, "tree" in ink or white.
class BrandHelperTest < ActionView::TestCase
  include IconsHelper

  test "the wordmark reads as one word and colors its halves" do
    assert_dom_equal '<span class="wordmark"><span class="wordmark-shade">Shade</span>tree</span>', wordmark
    assert_includes wordmark(on: :dark), 'class="wordmark wordmark-dark"'
  end

  test "the logo is the mark and the wordmark, as a link when given one" do
    render html: brand_logo(href: "/", "aria-label": "Shadetree home")
    assert_select "a.logo[href='/'][aria-label='Shadetree home'] > span.logo-mark svg[aria-hidden=true]"
    assert_select "a.logo > span.wordmark:not(.wordmark-dark) .wordmark-shade", "Shade"
    render html: brand_logo(on: :dark)
    assert_select "span.logo > span.logo-mark.logo-mark-dark + span.wordmark.wordmark-dark"
  end

  test "under 14px the wordmark is one colour: ink, or white on dark" do
    assert_dom_equal '<span class="wordmark wordmark-small">Shadetree</span>', wordmark(size: :small)
    assert_dom_equal '<span class="wordmark wordmark-dark wordmark-small">Shadetree</span>', wordmark(on: :dark, size: :small)
    assert_not_includes wordmark(size: :small), "wordmark-shade"
  end

  test "the email wordmark is inline-styled" do
    html = email_wordmark
    assert_includes html, %(<span style="color:#059669;">Shade</span>tree)
    assert_includes html, "color:#0f172a"
    assert_includes email_wordmark(on: :dark), "color:#ffffff"
  end
end
