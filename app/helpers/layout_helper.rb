# Helpers for the three layouts (marketing, app, client).
module LayoutHelper
  # A sidebar link; `count` shows a badge (CLI-04: new requests) when it's above zero.
  def side_link(label, path, icon:, active: false, count: nil)
    link_to path, class: "side-link", "aria-current": (active ? "page" : nil) do
      badge = tag.span(safe_join([ count.to_s, tag.span(" new", class: "sr-only") ]), class: "side-count") if count.to_i.positive?
      safe_join([ icon(icon), tag.span(label), badge ].compact)
    end
  end

  def day_period(time = Time.current)
    case time.hour
    when 0...12 then "morning"
    when 12...17 then "afternoon"
    else "evening"
    end
  end

  def initials(name)
    name.to_s.split.map { |part| part[0] }.first(2).join.upcase
  end

  def current_role_label
    role = current_business&.business_users&.find_by(user: current_user)&.role
    role ? role.humanize : ""
  end

  # The business's logo, or its initials on its brand color (CAT-02 Branding).
  def business_mark(business, class: nil)
    branding = Branding.new(business)
    classes = [ "biz-logo overflow-hidden", binding.local_variable_get(:class) ].compact.join(" ")
    if branding.logo?
      tag.span(image_tag(branding.logo(:web), alt: "", class: "size-full object-contain"), class: "#{classes} bg-white")
    else
      tag.span(branding.initials, class: "#{classes} #{inline_style(business_mark_style(business))}")
    end
  end

  # The square business mark in the switcher uses the business's brand color.
  def business_mark_style(business)
    branding = Branding.new(business)
    "background: #{branding.color}; color: #{branding.ink}"
  end
end
