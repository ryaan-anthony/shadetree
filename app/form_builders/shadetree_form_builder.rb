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
    described_by = [ ("#{id}_help" if help), ("#{id}_error" if errors.any?) ].compact
    options[:"aria-describedby"] = described_by.join(" ") if described_by.any?
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
