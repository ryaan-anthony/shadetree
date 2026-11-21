# Shadetree's own brand (owner decision, 2026-11-21; MKT-01 and the styleguide): the name is
# "Shadetree", one word, and the wordmark is "Shade" in green (#059669) and "tree" in ink on light
# backgrounds or white on dark ones (the marketing footer, the app sidebar). Every place the name
# is shown as a logo uses these helpers; in running text it's just "Shadetree".
#
#   brand_logo(href: root_path)                 # mark and wordmark, on a light background
#   brand_logo(on: :dark, href: root_path)      # on navy: "tree" in white
#   wordmark                                    # the word alone
#   wordmark(size: :small)                      # under 14px ("Powered by"): one colour, ink or white
#   email_wordmark                              # inline-styled, for email layouts
module BrandHelper
  NAME = "Shadetree"
  GREEN = "#059669"
  INK = "#0f172a"

  # The word. The halves are inline with no space between, so the text (and what screen readers
  # and search engines read) is "Shadetree". Under 14px (size: :small) it's one colour, ink on
  # light or white on dark (owner, 2026-11-21): the green half is too thin to read that small.
  def wordmark(on: :light, size: :regular, **attributes)
    classes = [ "wordmark", ("wordmark-dark" if on == :dark), ("wordmark-small" if size == :small), attributes.delete(:class) ].compact.join(" ")
    tag.span(class: classes, **attributes) { size == :small ? NAME : tag.span("Shade", class: "wordmark-shade") + "tree" }
  end

  # The mark and the word, as a link when given href:.
  def brand_logo(on: :light, href: nil, mark: true, **attributes)
    attributes[:class] = [ "logo", attributes[:class] ].compact.join(" ")
    content = (mark ? tag.span(logo_mark, class: "logo-mark#{" logo-mark-dark" if on == :dark}") : "".html_safe) + wordmark(on:)
    href ? link_to(content, href, **attributes) : tag.span(content, **attributes)
  end

  # Email clients ignore classes, so the colors are inline.
  def email_wordmark(on: :light, size: 18)
    style = "font-size:#{size}px;font-weight:800;letter-spacing:-0.02em;color:#{on == :dark ? "#ffffff" : INK};"
    tag.span(style:) { tag.span("Shade", style: "color:#{GREEN};") + "tree" }
  end
end
