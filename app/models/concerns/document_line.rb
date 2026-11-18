# What a line on a quote, a job (and later an invoice) shares: its fields, their limits, and
# how it prices (PLT-08). The including model says which document it belongs to with
# `document_currency`, and declares its own document and catalog_item associations.
module DocumentLine
  extend ActiveSupport::Concern

  MAX_UNIT_PRICE_CENTS = 10_000_000_000

  included do
    include HasMoney
    include HasDiscount

    money :unit_price, currency: -> { document_currency }

    normalizes :name, with: ->(value) { value.to_s.squish }
    normalizes :description, with: ->(value) { value.to_s.strip.presence }
    normalizes :unit, with: ->(value) { value.to_s.squish.presence }

    validates :name, length: { maximum: 200 }
    validates :description, length: { maximum: 2_000 }
    validates :unit, length: { maximum: 20 }
    validates :quantity, numericality: { greater_than_or_equal_to: 0, less_than: 1_000_000 }
    validate { errors.add(:unit_price, "is too large") if unit_price_cents.to_i.abs >= MAX_UNIT_PRICE_CENTS }
    validate { errors.add(:discount_amount, "can't be more than the line") if discount_kind == "amount" && discount_amount_cents.to_i > line_amount_cents }
  end

  def discount_currency = document_currency

  def to_pricing(rates)
    Pricing::Line.new(quantity: quantity.to_d, unit_price: unit_price || Money.zero(document_currency),
                      discount: pricing_discount, tax_rates: taxable ? rates : [])
  end

  def line_amount_cents = ((unit_price_cents || 0) * (quantity || 0)).round

  # The quantity box: what was typed when it couldn't be read, else the number without zeros.
  def quantity_for_form
    return quantity_before_type_cast.to_s if errors[:quantity].any?

    quantity.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")
  end

  # "2.5 hour", "6 cu yd", or just "3" without a unit.
  def quantity_label = [ quantity.to_d.round(4).to_s("F").sub(/\.?0+\z/, ""), unit ].compact.join(" ")

  private

  # A catalog item by its uid, within the business (the default scope); unchanged lines whose
  # item is already loaded need no query.
  def catalog_item_id_for(uid)
    return if uid.empty?
    return catalog_item_id if association(:catalog_item).loaded? && catalog_item&.uid == uid

    CatalogItem.find_by(uid:)&.id
  end
end
