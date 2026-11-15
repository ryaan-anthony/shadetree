# A discount that is either a percentage or a fixed amount (QTE-01), stored as
# discount_kind ("percent"/"amount") with discount_percent or discount_amount_cents.
#
#   quote.set_discount("percent", "10")
#   quote.pricing_discount   # => Pricing::Discount.percent(10), or nil
module HasDiscount
  extend ActiveSupport::Concern

  KINDS = %w[percent amount].freeze

  included do
    money :discount_amount, currency: -> { discount_currency }
    validates :discount_kind, inclusion: { in: KINDS }, allow_nil: true
    validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
    validate { errors.add(:discount_amount, "can't be negative") if discount_amount_cents&.negative? }
  end

  def discount_kind=(kind)
    super(kind.presence_in(KINDS))
  end

  # What the form's value box shows: the percent ("10") or the amount ("25.00"), or what was
  # typed when it couldn't be read, so a re-rendered form keeps the text to correct.
  def discount_value
    return discount_amount_before_type_cast unless discount_kind == "percent"
    return discount_percent_before_type_cast.to_s if discount_percent.nil?

    discount_percent.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")
  end

  # The form's kind select and value box together (an explicit pair, so the order the
  # attributes arrive in doesn't matter). A blank value or no kind clears the discount.
  def set_discount(kind, value)
    self.discount_kind = value.to_s.strip.empty? ? nil : kind
    self.discount_percent = discount_kind == "percent" ? value.to_s.strip : nil
    self.discount_amount = discount_kind == "amount" ? value.to_s.strip : nil
  end

  def discounted? = pricing_discount.present?

  def pricing_discount
    case discount_kind
    # Out-of-range values are left to validation, so the form shows the error instead of a 500.
    when "percent" then Pricing::Discount.percent(discount_percent) if discount_percent&.positive? && discount_percent <= 100
    when "amount" then Pricing::Discount.amount(discount_amount) if discount_amount&.positive?
    end
  end
end
