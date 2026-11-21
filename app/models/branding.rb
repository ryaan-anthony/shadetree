# How a business looks to its clients (CAT-02): the one source client pages (PLT-05), PDFs
# (QTE-02) and emails (NTF-01) read. Wraps the business's logo and brand color with the
# derived values they need: a readable text color on the brand, CSS variables, logo sizes,
# a name-based wordmark when there's no logo, and whether "Powered by Shadetree" shows.
class Branding
  DEFAULT_COLOR = "#047857"
  HEX = /\A#\h{6}\z/
  INK = "#0f172a"
  WHITE = "#ffffff"
  # WCAG: 4.5:1 for button text; 3:1 for the brand color against the white page (links,
  # borders, large text).
  MIN_TEXT_CONTRAST = 4.5
  MIN_PAGE_CONTRAST = 3.0
  # Client pages are #f4f5f7 behind white cards: link text has to read on the darker of the two.
  CLIENT_PAGE = "#f4f5f7"

  PRESETS = {
    "Forest" => "#047857", "Ocean" => "#0369a1", "Indigo" => "#4338ca", "Plum" => "#7e22ce",
    "Rose" => "#be123c", "Rust" => "#9a3412", "Gold" => "#a16207", "Slate" => "#334155"
  }.freeze

  # Logo sizes: the longest side is limited, aspect ratio kept, metadata stripped.
  LOGO_SIZES = {
    web: { resize_to_limit: [ 480, 160 ] },
    email: { resize_to_limit: [ 360, 120 ], format: :png },
    pdf: { resize_to_limit: [ 960, 320 ], format: :png }
  }.freeze

  attr_reader :business

  def initialize(business)
    @business = business
  end

  def name = business&.name.to_s

  # The brand color as #rrggbb (lowercase); the default when unset or invalid.
  def color
    value = business&.brand_color.to_s.downcase
    value.match?(HEX) ? value : DEFAULT_COLOR
  end

  # White or ink text, whichever reads better on the brand color.
  def ink = self.class.contrast(color, WHITE) >= self.class.contrast(color, INK) ? WHITE : INK
  def ink_contrast = self.class.contrast(color, ink)
  def page_contrast = self.class.contrast(color, WHITE)

  # Owner, 2026-11-21: the business's color is used as chosen for accents (borders, the progress
  # rail). Text keeps 4.5:1 automatically: link text uses link_color, and a button whose text
  # can't reach 4.5:1 in white or ink uses button_color, both the same hue darkened just enough.
  def link_color = self.class.readable(color, on: CLIENT_PAGE)
  def button_color = ink_contrast >= MIN_TEXT_CONTRAST ? color : self.class.readable(color, on: WHITE)
  def button_ink = button_color == color ? ink : WHITE

  # Plain-language notes about the color, for the settings page.
  def contrast_warnings
    warnings = []
    warnings << "Neither white nor dark text reads well on this color, so buttons use a slightly darker shade." if ink_contrast < MIN_TEXT_CONTRAST
    warnings << "This color is light against a white page: links use a darker shade, and outlines may be hard to see." if page_contrast < MIN_PAGE_CONTRAST
    warnings
  end

  # CSS variables for client pages. Only validated #rrggbb values reach the style attribute.
  def css_variables
    "--color-brand: #{color}; --color-brand-button: #{button_color}; --color-brand-ink: #{button_ink}; " \
      "--color-brand-link: #{link_color}; --color-brand-soft: color-mix(in srgb, #{color} 10%, white);"
  end

  # The color darkened toward black (same hue) in 1% steps until text in it reaches 4.5:1 on
  # `on`; unchanged when it already does.
  def self.readable(hex, on: WHITE, min: MIN_TEXT_CONTRAST)
    rgb = hex.delete("#").scan(/../).map { _1.to_i(16) }
    (0..100).each do |step|
      candidate = format("#%02x%02x%02x", *rgb.map { (_1 * (100 - step) / 100.0).round })
      return candidate if contrast(candidate, on) >= min
    end
  end

  def logo? = logo_attachment.present?

  # A sized logo for :web, :email or :pdf, or nil without one.
  def logo(size = :web) = logo_attachment&.variant(size)

  # The sized logo's width and height, worked out from the original's (once the upload has been
  # analyzed), so pages can reserve its space before it loads. Nil when they aren't known yet.
  def logo_dimensions(size = :web)
    width, height = logo_attachment&.blob&.metadata&.values_at("width", "height")
    return unless width.to_i.positive? && height.to_i.positive?

    max_width, max_height = LOGO_SIZES.fetch(size).fetch(:resize_to_limit)
    scale = [ max_width.fdiv(width), max_height.fdiv(height), 1 ].min
    [ (width * scale).round, (height * scale).round ]
  end

  # The saved logo. A new upload waiting on a save that failed validation isn't shown; the
  # logo already saved is, until the new one is.
  def logo_attachment
    return @logo_attachment if defined?(@logo_attachment)

    @logo_attachment =
      if !business.respond_to?(:logo) then nil
      elsif business.attachment_changes["logo"].nil? then (business.logo.attachment if business.logo.attached?)
      elsif business.persisted? then ActiveStorage::Attachment.find_by(record: business, name: "logo")
      end
  end

  # Up to two initials, for the name-based wordmark.
  def initials = name.split.filter_map { _1[0] }.first(2).join.upcase

  # Shown unless the business's plan removes it (BIL-01); always on pages with no business, and
  # on stand-in businesses (samples, the styleguide) that aren't on a plan.
  def show_powered_by? = !(business.is_a?(Business) && business.plan && Entitlements.for(business).remove_powered_by?)

  # WCAG contrast ratio between two #rrggbb colors.
  def self.contrast(a, b)
    la, lb = [ a, b ].map { luminance(_1) }.sort.reverse
    (la + 0.05) / (lb + 0.05)
  end

  def self.luminance(hex)
    hex.delete("#").scan(/../).map { _1.to_i(16) / 255.0 }
       .map { _1 <= 0.03928 ? _1 / 12.92 : ((_1 + 0.055) / 1.055)**2.4 }
       .zip([ 0.2126, 0.7152, 0.0722 ]).sum { |channel, weight| channel * weight }
  end
end
