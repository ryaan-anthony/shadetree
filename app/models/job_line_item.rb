# One line of work on a job (JOB-01): copied from the approved quote, or added to the job.
# The job's copy can change on site; the quote keeps what the client agreed to.
class JobLineItem < ApplicationRecord
  include BusinessOwned
  include HasMoney
  include HasDiscount

  COPIED = %w[catalog_item_id position name description quantity unit unit_price_cents taxable
              discount_kind discount_percent discount_amount_cents].freeze

  belongs_to :job, inverse_of: :line_items
  belongs_to_business_record :catalog_item, optional: true

  money :unit_price, currency: -> { job.currency }

  def discount_currency = job.currency

  normalizes :name, with: ->(value) { value.to_s.squish }
  normalizes :description, with: ->(value) { value.to_s.strip.presence }
  normalizes :unit, with: ->(value) { value.to_s.squish.presence }

  before_validation { self.business ||= job&.business }

  validates :name, length: { maximum: 200 }
  validates :description, length: { maximum: 2_000 }
  validates :unit, length: { maximum: 20 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0, less_than: 1_000_000 }
  validate { errors.add(:unit_price, "is too large") if unit_price_cents.to_i.abs >= 10_000_000_000 }
  validate { errors.add(:discount_amount, "can't be more than the line") if discount_kind == "amount" && discount_amount_cents.to_i > line_amount_cents }

  def to_pricing(rates)
    Pricing::Line.new(quantity: quantity.to_d, unit_price: unit_price || Money.zero(job.currency),
                      discount: pricing_discount, tax_rates: taxable ? rates : [])
  end

  def line_amount_cents = ((unit_price_cents || 0) * (quantity || 0)).round

  # "2.5 hour", "6 cu yd", or just "3" without a unit.
  def quantity_label = [ quantity.to_d.round(4).to_s("F").sub(/\.?0+\z/, ""), unit ].compact.join(" ")
end
