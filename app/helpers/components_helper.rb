# Helpers for the UI kit (ADR 0005). Each one renders a partial in app/views/components or
# returns kit classes; the style guide (/styleguide in development) shows them all.
module ComponentsHelper
  # PLT-14: four ranks, plus a destructive dialog's solid red confirm and the client pages'
  # brand button (their Primary). The style guide shows each with its rule:
  #   primary      green, the next step in the workflow; at most one in a page's header
  #   secondary    white with a border, supporting actions
  #   tertiary     borderless grey, for navigation, low-risk actions and Cancel
  #   destructive  red text and border: Cancel job, Disconnect, Deactivate, Archive, every delete
  # The green inline text link (.text-action) isn't a button: only for actions inside a sentence.
  BUTTON_VARIANTS = %i[primary secondary tertiary destructive destructive_solid brand].freeze
  BUTTON_SIZES = %i[sm lg icon].freeze
  BADGE_TONES = %i[neutral success info warning danger violet dark].freeze

  # Classes for a button-styled link or button:
  #   link_to "New quote", new_quote_path, class: button_classes
  #   button_to "Delete", quote_path(q), method: :delete, class: button_classes(:destructive, :sm)
  def button_classes(variant = :primary, *sizes, extra: nil)
    raise ArgumentError, "Unknown button variant #{variant.inspect}" unless BUTTON_VARIANTS.include?(variant)
    unknown = sizes - BUTTON_SIZES
    raise ArgumentError, "Unknown button size #{unknown.inspect}" if unknown.any?

    [ "btn", "btn-#{variant.to_s.dasherize}", *sizes.map { |s| "btn-#{s}" }, extra ].compact.join(" ")
  end

  # A status pill. tone: one of BADGE_TONES.
  def badge(text, tone: :neutral, dot: true, **attributes)
    raise ArgumentError, "Unknown badge tone #{tone.inspect}" unless BADGE_TONES.include?(tone)

    classes = [ "badge", ("badge-#{tone}" unless tone == :neutral), ("badge-plain" unless dot), attributes.delete(:class) ]
    tag.span(text, class: classes.compact.join(" "), **attributes)
  end

  def card(title: nil, subtitle: nil, actions: nil, flush: false, footer: nil, **attributes, &block)
    render "components/card", title:, subtitle:, actions:, flush:, footer:, attributes:, body: capture(&block)
  end

  # level: the heading level. 2 under a page's H1; 3 inside a titled card, whose title is an H2;
  # 1 when the empty state is the whole page (not allowed, suspended).
  def empty_state(title:, text: nil, icon: "inbox", level: 2, &actions)
    raise ArgumentError, "Empty-state heading level must be 1, 2 or 3, not #{level.inspect}" unless level.in?([ 1, 2, 3 ])

    render "components/empty_state", title:, text:, icon:, level:, actions: (capture(&actions) if actions)
  end

  def page_header(title, lede: nil, &actions)
    content_for(:title, title) unless content_for?(:title)
    render "components/page_header", title:, lede:, actions: (capture(&actions) if actions)
  end

  # A <dialog>. Open it with a button carrying data-action="modal#open" inside a
  # data-controller="modal" wrapper, or call modal_trigger.
  # sheet: true docks it to the bottom of the screen on phones (JOB-03's quick edit).
  def modal(id:, title:, description: nil, footer: nil, sheet: false, &block)
    render "components/modal", id:, title:, description:, footer:, sheet:, body: capture(&block)
  end

  # Previous/next pagination with a "Showing 21–40 of 132" summary. Keeps other query params.
  def pagination(page:, per_page:, total_count:, param: :page)
    total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    page = page.to_i.clamp(1, total_pages)
    render "components/pagination",
           page:, total_pages:, total_count:,
           first: total_count.zero? ? 0 : ((page - 1) * per_page) + 1,
           last: [ page * per_page, total_count ].min,
           url_for_page: ->(n) { url_for(request.query_parameters.merge(param => n)) }
  end

  def avatar(name, **attributes)
    initials = name.to_s.split.map { |part| part[0] }.first(2).join.upcase
    tag.span(initials, class: [ "avatar", attributes.delete(:class) ].compact.join(" "), title: name, **attributes)
  end

  # Flash messages as toasts. notice → success, alert → danger; other keys render neutral.
  def flash_toasts
    # A true/false flag passed through the flash (the contact form's "emailed") isn't a message.
    render "components/flash", messages: flash.to_hash.select { |_, message| message.present? && message != true }
  end

  def flash_tone(key)
    case key.to_s
    when "notice", "success" then :success
    when "alert", "error", "danger" then :danger
    when "warning" then :warning
    else :info
    end
  end
end
