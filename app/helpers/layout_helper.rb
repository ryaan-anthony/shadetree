# Helpers for the three layouts (marketing, app, client).
module LayoutHelper
  HEX_COLOR = /\A#\h{6}\z/

  def side_link(label, path, icon:, active: false)
    link_to path, class: "side-link", "aria-current": (active ? "page" : nil) do
      icon(icon) + tag.span(label)
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

  # The business's logo, or its initials on its brand colour.
  def business_mark(business, class: nil)
    classes = [ "biz-logo overflow-hidden", binding.local_variable_get(:class) ].compact.join(" ")
    if business.logo_url.present?
      tag.span(image_tag(business.logo_url, alt: "", class: "size-full object-cover"), class: "#{classes} bg-white")
    else
      tag.span(initials(business.name), class: classes, style: business_mark_style(business))
    end
  end

  # The square business mark in the switcher uses the business's brand colour.
  def business_mark_style(business)
    color = brand_color(business)
    "background: #{color}; color: #{readable_ink(color)}"
  end

  # CSS variables for client-facing pages. Only a validated #rrggbb value reaches the page.
  def client_brand_style(business)
    color = brand_color(business)
    "--color-brand: #{color}; --color-brand-ink: #{readable_ink(color)}; " \
      "--color-brand-soft: color-mix(in srgb, #{color} 10%, white);"
  end

  def brand_color(business)
    color = business&.brand_color.to_s.downcase
    color.match?(HEX_COLOR) ? color : "#047857"
  end

  # White or ink text, whichever has the higher WCAG contrast against the colour.
  def readable_ink(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    luminance = [ r, g, b ].map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
                           .zip([ 0.2126, 0.7152, 0.0722 ]).sum { |c, w| c * w }
    contrast_white = 1.05 / (luminance + 0.05)
    contrast_ink = (luminance + 0.05) / 0.0588 # ink #0f172a: relative luminance 0.0088, plus 0.05
    contrast_white >= contrast_ink ? "#ffffff" : "#0f172a"
  end
end
