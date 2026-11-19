# CAT-08: what a catalog item costs at one location, instead of its business price. Documents
# copy the price when the item is added, so changing or removing an override never alters them.
class LocationPrice < ApplicationRecord
  include BusinessOwned
  include HasMoney

  belongs_to_business_record :location
  belongs_to_business_record :catalog_item
  money :unit_price, currency: -> { business.currency_code }

  validates :catalog_item_id, uniqueness: { scope: :location_id }
  validates :unit_price_cents, presence: { message: "needs a price" }
  validate { errors.add(:unit_price, "can't be negative") if unit_price_cents&.negative? }

  # { catalog_item_id => cents } at a location, for pricing many items at once.
  def self.cents_at(location, items) = location.nil? || location.primary? ? {} : where(location:, catalog_item: items).pluck(:catalog_item_id, :unit_price_cents).to_h
end
