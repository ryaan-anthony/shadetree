# The app's default form builder (config/initializers/form_builder.rb). It keeps every
# standard Rails helper and adds kit-styled fields with a label, help text and errors wired
# up for screen readers:
#
#   <%= form_with model: @client do |f| %>
#     <%= f.field :name %>
#     <%= f.field :email, as: :email, help: "Quotes and invoices go here." %>
#     <%= f.field :notes, as: :textarea, optional: true %>
#     <%= f.field :timezone, as: :select, choices: time_zone_options %>
#     <%= f.field :visit_on, as: :date %>
#     <%= f.field :price, as: :money, currency: "$" %>
#     <%= f.check :reminders, label: "Send reminders", hint: "A day before each visit." %>
#     <%= f.file_drop :logo, prompt: "Drop your logo here", types: Business::LOGO_TYPES,
#                     types_label: "PNG, JPEG or WebP", max_bytes: 5.megabytes %>
#     <%= f.submit_button "Save client" %>
#   <% end %>
#
# Most forms mark only the optional fields. A public form where most fields are optional can
# also mark the required ones: `<%= f.required_legend %>` before the fields shows "Fields marked
# * are required." and puts a * after the label of every required field that follows.
class ShadetreeFormBuilder < ActionView::Helpers::FormBuilder
  INPUT_TYPES = {
    text: :text_field, email: :email_field, password: :password_field, phone: :telephone_field,
    url: :url_field, number: :number_field, search: :search_field,
    date: :date_field, time: :time_field, datetime: :datetime_local_field
  }.freeze

  def field(method, as: :text, label: nil, help: nil, optional: false, choices: nil, currency: "$", **options)
    id = field_id(method)
    errors = error_messages(method)
    options[:id] ||= id
    options[:"aria-invalid"] = "true" if errors.any?
    described_by = [ ("#{id}_help" if help), ("#{id}_error" if errors.any?), options[:"aria-describedby"] ] # the caller's ids kept (PLT-22)
    options[:"aria-describedby"] = token_list(described_by) if described_by.any?(&:present?)
    options[:required] = true if !optional && !options.key?(:required) && required?(method)

    input = build_input(method, as, choices, currency, options)
    @template.render "components/field",
                     id:, input:, help:, errors:, optional:,
                     required_mark: @mark_required && options[:required].present?,
                     label: label || label_text(method)
  end

  # The legend for required-field marks; required fields after it get a *.
  def required_legend
    @mark_required = true
    @template.tag.p(class: "help mt-0") do
      @template.safe_join([ "Fields marked ", @template.tag.span("*", class: "label-required"), " are required." ])
    end
  end

  def check(method, label: nil, hint: nil, **options)
    @template.tag.label(class: "check") do
      check_box(method, options) +
        @template.tag.span do
          @template.tag.span(label || label_text(method), class: "font-medium text-ink") +
            (hint ? @template.tag.span(hint, class: "check-hint") : "".html_safe)
        end
    end
  end

  # A file field shown as a drop area: the kit's file upload (PLT-22, R28). The page has a
  # plain file field, which uploads without JavaScript; file_drop_controller.js turns it into
  # the drop area, shows the chosen file's name and preview, and refuses a wrong type or size
  # before saving with the server's own words (type_error, size_error: as errors.add's). It
  # dispatches file-drop:chosen ({ file, url, problem }) for a live preview.
  def file_drop(method, prompt:, types:, types_label:, max_bytes:, label: nil, help: nil, type_error: nil, size_error: nil, **options)
    id = options[:id] ||= field_id(method)
    errors = error_messages(method)
    size = @template.number_to_human_size(max_bytes)
    options[:"aria-invalid"] = "true" if errors.any?
    options[:"aria-labelledby"] = token_list([ "#{id}_label", options[:"aria-labelledby"] ]) # not the drop area's text as well
    options[:"aria-describedby"] = token_list([ "#{id}_limits", ("#{id}_help" if help), ("#{id}_error" if errors.any?), "#{id}_check", options[:"aria-describedby"] ])
    options[:accept] = types.join(",")
    data = (options[:data] || {}).symbolize_keys
    options[:data] = data.merge(file_drop_target: "input", action: token_list([ data[:action], "change->file-drop#chosen" ]))
    input = file_field(method, merge_class(options, "input file-drop-input py-1.5"))
    @template.render "components/file_drop",
                     id:, input:, prompt:, help:, errors:, label: label || label_text(method),
                     limits: "#{types_label}, up to #{size}.",
                     values: { types: types.join(","), max_bytes:,
                               type_error: full_message(method, type_error || "must be a #{types_label} file"),
                               size_error: full_message(method, size_error || "must be smaller than #{size}") }
  end

  # variant and size: as button_classes (PLT-14), e.g. f.submit_button "Sign in", size: :lg
  def submit_button(text = nil, variant: :primary, size: nil, **options)
    options[:class] = @template.button_classes(variant, *size, extra: options[:class])
    submit(text, options)
  end

  private

  def build_input(method, as, choices, currency, options)
    case as
    when :textarea
      text_area(method, merge_class(options, "textarea"))
    when :select
      select(method, choices, { include_blank: options.delete(:include_blank) }, merge_class(options, "select"))
    when :money
      money_input(method, currency, options)
    when *INPUT_TYPES.keys
      public_send(INPUT_TYPES.fetch(as), method, merge_class(options, "input"))
    else
      raise ArgumentError, "Unknown field type #{as.inspect}"
    end
  end

  # Amounts are typed as decimals; storage in integer minor units is PLT-08's job.
  def money_input(method, currency, options)
    options = merge_class(options.reverse_merge(inputmode: "decimal", autocomplete: "off"), "input tabular")
    @template.tag.div(class: "input-group") do
      @template.tag.span(currency, class: "input-addon", "aria-hidden": "true") + text_field(method, options)
    end
  end

  def token_list(values) = values.flat_map { _1.to_s.split }.uniq.join(" ")

  def full_message(method, message)
    object.respond_to?(:errors) ? object.errors.full_message(method, message) : "#{label_text(method)} #{message}"
  end

  def merge_class(options, klass)
    options.merge(class: [ klass, options[:class] ].compact.join(" "))
  end

  def error_messages(method)
    return [] unless object.respond_to?(:errors)

    object.errors.full_messages_for(method)
  end

  def label_text(method)
    if object.class.respond_to?(:human_attribute_name)
      object.class.human_attribute_name(method)
    else
      method.to_s.humanize
    end
  end

  def required?(method)
    return false unless object.class.respond_to?(:validators_on)

    object.class.validators_on(method).any? do |validator|
      validator.is_a?(ActiveModel::Validations::PresenceValidator) && validator.options.slice(:if, :unless, :on).empty?
    end
  end
end
