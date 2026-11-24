# Inline SVG icons rendered on the server: no icon font, no runtime script, no CDN.
#
# The set is Feather (MIT, vendor/feather) plus a few app glyphs. Names follow Feather
# (https://feathericons.com); domain aliases keep call sites readable:
#
#   icon("calendar")
#   icon("quote", class: "size-5 text-muted")
#   icon("trash", label: "Delete")   # announced to screen readers; decorative otherwise
module IconsHelper
  CUSTOM_ICONS = {
    "invoice" => '<path d="M5 2h14v20l-3-2-2 2-2-2-2 2-2-2-3 2z"/><line x1="9" y1="7" x2="15" y2="7"/>' \
                 '<line x1="9" y1="11" x2="15" y2="11"/><line x1="9" y1="15" x2="13" y2="15"/>',
    "selector" => '<polyline points="7 15 12 20 17 15"/><polyline points="7 9 12 4 17 9"/>'
  }.freeze

  ALIASES = {
    "quote" => "file-text",
    "job" => "briefcase",
    "client" => "user",
    "clients" => "users",
    "schedule" => "calendar",
    "money" => "dollar-sign",
    "success" => "check-circle",
    "warning" => "alert-triangle",
    "danger" => "alert-octagon",
    "info" => "info"
  }.freeze

  class UnknownIcon < ArgumentError; end

  def self.paths
    @paths ||= JSON.parse(Rails.root.join("vendor/feather/icons.json").read).merge(CUSTOM_ICONS).freeze
  end

  def self.known?(name)
    paths.key?(ALIASES.fetch(name.to_s, name.to_s))
  end

  def icon(name, label: nil, class: "size-4", **attributes)
    key = ALIASES.fetch(name.to_s, name.to_s)
    body = IconsHelper.paths.fetch(key) { raise UnknownIcon, "Unknown icon #{name.inspect}" }

    a11y = label ? { role: "img", "aria-label": label } : { "aria-hidden": "true", focusable: "false" }
    svg_attributes = {
      xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", width: 24, height: 24,
      fill: "none", stroke: "currentColor",
      "stroke-width": "1.8", "stroke-linecap": "round", "stroke-linejoin": "round",
      class: binding.local_variable_get(:class)
    }.merge(a11y).merge(attributes)

    content_tag(:svg, (label ? content_tag(:title, label) : "".html_safe) + body.html_safe, svg_attributes)
  end
end
