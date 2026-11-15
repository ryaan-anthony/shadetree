# One line on a quote (QTE-01): a copy of a catalog item or a custom line. Amounts are cents
# in the quote's currency; Pricing::Line does the arithmetic.
class QuoteLineItem < ApplicationRecord
  include BusinessOwned
  include HasMoney
  include HasDiscount

  belongs_to :quote, inverse_of: :line_items
  belongs_to :catalog_item, optional: true

  money :unit_price, currency: -> { quote.currency }

  def discount_currency = quote.currency

  normalizes :name, with: ->(value) { value.to_s.squish }
  normalizes :description, with: ->(value) { value.to_s.strip.presence }
  normalizes :unit, with: ->(value) { value.to_s.squish.presence }

  before_validation { self.business ||= quote&.business }

  validates :key, presence: true, length: { maximum: 64 }
  validates :name, length: { maximum: 200 }
  validates :description, length: { maximum: 2_000 }
  validates :unit, length: { maximum: 20 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0, less_than: 1_000_000 }
  validate { errors.add(:unit_price, "is too large") if unit_price_cents.to_i.abs >= 10_000_000_000 }
  validate { errors.add(:discount_amount, "can't be more than the line") if discount_kind == "amount" && discount_amount_cents.to_i > line_amount_cents }

  # Fills this line from one row of the builder form.
  def assign_row(row, position:)
    self.position = position
    self.catalog_item_id = CatalogItem.find_by(uid: row["catalog_item"])&.id if row.key?("catalog_item")
    %w[name description unit].each { public_send("#{_1}=", row[_1]) if row.key?(_1) }
    self.quantity = row["quantity"].to_s.strip.presence || "0" if row.key?("quantity")
    self.unit_price = row["unit_price"].to_s.strip.presence || "0" if row.key?("unit_price")
    self.taxable = ActiveModel::Type::Boolean.new.cast(row["taxable"]) if row.key?("taxable")
    set_discount(row["discount_kind"], row["discount_value"]) if row.key?("discount_kind")
  end

  def to_pricing(rates)
    Pricing::Line.new(quantity: quantity.to_d, unit_price: unit_price || Money.zero(quote.currency),
                      discount: pricing_discount, tax_rates: taxable ? rates : [])
  end

  def line_amount_cents = ((unit_price_cents || 0) * (quantity || 0)).round
end
