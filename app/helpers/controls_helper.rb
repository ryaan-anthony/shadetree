# PLT-19: the kit's switches and menus, one of each (#314, items 9 and 13). The style guide
# (/styleguide in development) shows them all.
#
#   tabs           switch what a list shows: left-aligned under the page header, with counts
#   segmented_control  picks one of a few options on the same view (Day/Week, Monthly/Yearly)
#   menu           a button that opens a list of actions (white card, as wide as its longest item)
#
# Tabs and the segmented control come in three kinds, by how the choice is sent:
#   href: ->(key) { path }   links; the current one is aria-current="page"
#   name: "filter"           a GET or filter form's submit buttons; the current one is aria-pressed
#   radio: { name:, form: }  radio buttons (no request, or a form that submits on change)
module ControlsHelper
  # choices: { key => label }, or { key => [label, attributes] } for an option's own attributes.
  # counts: { key => n } shows each count; a tab whose count is 0 is hidden, except the keys in
  # keep ("All") and the current tab (owner, 2026-11-22). A key without a count has none shown.
  def tabs(choices, current:, label:, counts: nil, keep: %w[all], href: nil, name: nil, radio: nil, **attributes)
    shown = choices.reject { |key, _| counts&.[](key)&.zero? && !keep.include?(key) && key != current }
    options = shown.map do |key, (text, option_attributes)|
      count = counts&.[](key)
      text = safe_join([ text, (tag.span(count, class: "tab-count") if count) ].compact, " ")
      switch_option(key, text, key == current, "tab", href:, name:, radio:, **option_attributes.to_h)
    end
    attributes[:data] = { controller: "tabs" }.merge(attributes[:data].to_h) if href
    switch_group(options, "tabs", label, radio:, **attributes)
  end

  # label: the group's accessible name (a legend for radios); label_id: name it by an element
  # already on the page instead (aria-labelledby).
  def segmented_control(choices, selected:, label:, label_id: nil, href: nil, name: nil, radio: nil, **attributes)
    options = choices.map do |key, (text, option_attributes)|
      switch_option(key, text, key == selected, "segment", href:, name:, radio:, **option_attributes.to_h)
    end
    switch_group(options, "segmented", label, label_id:, radio:, list: href.present?, **attributes)
  end

  # A disclosure menu: a button (aria-expanded, aria-controls) and the panel of .menu-item links
  # and buttons it opens. menu_controller.js handles the arrow keys, Home/End, Escape and Tab.
  #   <%= menu label: "More actions for #{item.name}", size: :sm do %> <%= link_to …, class: "menu-item" %> <% end %>
  # text: a labelled button ("Actions ▾", Secondary) instead of the icon-only Tertiary one.
  # align: :right (the default; opens leftwards from the button's right edge) or :left.
  # button: more attributes for the button (an id, data-tour, data-modal-target).
  def menu(label:, text: nil, icon_name: "more-horizontal", icon_class: "size-4", size: nil, align: :right, button: {}, **attributes, &items)
    # Random, so a menu re-rendered by a Turbo Stream never shares an id with one already on the page.
    id = "menu-#{SecureRandom.hex(6)}"
    button = button.dup
    button_data = { menu_target: "button", action: "menu#toggle" }.merge(button.delete(:data).to_h)
    trigger = tag.button(type: "button", class: [ text ? button_classes(:secondary, *size) : button_classes(:tertiary, *size, :icon), button.delete(:class) ].compact.join(" "),
                         "aria-expanded": "false", "aria-controls": id, "aria-label": (label unless text), data: button_data, **button) do
      text ? safe_join([ text, icon("chevron-down") ], " ") : icon(icon_name, class: icon_class)
    end
    panel = tag.div(capture(&items), id:, class: "menu #{align == :left ? "left-0" : "right-0"} top-full mt-1", data: { menu_target: "menu" }, hidden: true)
    data = { controller: "menu", action: "keydown->menu#keydown focusout->menu#focusout" }.merge(attributes.delete(:data).to_h)
    tag.div(trigger + panel, class: [ "relative", attributes.delete(:class) ].compact.join(" "), data:, **attributes)
  end

  private

  def switch_option(key, text, current, kind, href:, name:, radio:, **attributes)
    classes = [ kind, attributes.delete(:class) ].compact.join(" ")
    if href
      option = link_to(text, href.call(key), class: classes, "aria-current": ("page" if current), **attributes)
      kind == "segment" ? tag.li(option) : option
    elsif name
      data = { action: "tabs#press" }.merge(attributes.delete(:data).to_h) if kind == "tab"
      tag.button(text, type: "submit", name:, value: key, class: classes, "aria-pressed": current.to_s, data:, **attributes)
    elsif radio
      input = tag.input(type: "radio", name: radio.fetch(:name), value: key, class: "sr-only", checked: current, form: radio[:form], **attributes)
      tag.label(input + text, class: "#{classes} #{kind}-radio")
    else
      raise ArgumentError, "Pass href:, name: or radio:"
    end
  end

  # Links sit in a nav (tabs) or a list (segmented); buttons in a named group; radios in a fieldset.
  def switch_group(options, kind, label, radio:, label_id: nil, list: false, **attributes)
    classes = [ kind, attributes.delete(:class) ].compact.join(" ")
    if radio
      tag.fieldset(safe_join([ tag.legend(label, class: "sr-only"), *options ]), class: classes, **attributes)
    elsif list
      tag.ul(safe_join(options), class: classes, "aria-label": (label unless label_id), "aria-labelledby": label_id, **attributes)
    elsif kind == "tabs"
      tag.nav(safe_join(options), class: classes, "aria-label": label, **attributes)
    else
      tag.div(safe_join(options), class: classes, role: "group", "aria-label": (label unless label_id), "aria-labelledby": label_id, **attributes)
    end
  end
end
