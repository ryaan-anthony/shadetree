# Something a business sells: a service, product or fee, with a default price (CAT-03).
# Quotes, invoices and jobs copy name, description, unit, price and taxable when an item is
# added, so later edits or archiving never alter existing documents.
class CatalogItem < ApplicationRecord
  include BusinessOwned
  include HasMoney

  UNITS = { "each" => "each", "hour" => "hour", "visit" => "visit", "sq_ft" => "sq ft",
            "linear_ft" => "linear ft", "custom" => "custom" }.freeze

  belongs_to_business_record :category, class_name: "CatalogCategory", optional: true
  money :unit_price, currency: -> { business.currency_code }
  has_many :location_prices, dependent: :delete_all # CAT-08
  validate :location_prices_readable, if: -> { @location_price_inputs }
  after_save :save_location_prices, if: -> { @location_price_inputs }

  # CAT-08: the form's prices by location, { location uid => "45.00" }; blank means the business
  # price there. Saved with the item.
  def location_price_inputs=(inputs)
    @location_price_inputs = inputs.to_h.to_h { |uid, value| [ uid.to_s, value.to_s.strip ] }
  end

  # What the form shows for a location: what was typed, else its saved override.
  def location_price_input(location)
    return @location_price_inputs[location.uid] if @location_price_inputs&.key?(location.uid)

    location_prices.find { _1.location_id == location.id }&.unit_price&.to_s
  end

  # CAT-08: the price at a location: its override if it has one, else the business price.
  # `overrides` ({ catalog_item_id => cents }, from LocationPrice.cents_at) saves a query per item.
  def price_at(location, overrides: nil)
    return unit_price if location.nil? || location.primary?

    cents = overrides ? overrides[id] : location_prices.find_by(location:)&.unit_price_cents
    cents ? Money.new(cents, business.currency_code) : unit_price
  end

  normalizes :name, with: ->(name) { name.to_s.squish }
  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }
  validates :unit, inclusion: { in: UNITS.keys }
  validates :custom_unit, presence: true, length: { maximum: 20 }, if: -> { unit == "custom" }
  # On unit_price, the field the form shows, so a negative price is marked where it was typed.
  validate { errors.add(:unit_price, "can't be negative") if unit_price_cents&.negative? }
  validates :duration_minutes, numericality: { only_integer: true, in: 1..(24 * 60) }, allow_nil: true

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position, :name) }
  scope :search, ->(query) {
    next all if query.blank?

    term = "%#{sanitize_sql_like(query.strip)}%"
    where("catalog_items.name ILIKE :term OR catalog_items.description ILIKE :term", term:)
  }

  before_create { self.position = (self.class.where(category_id:).maximum(:position) || -1) + 1 }

  def archived? = archived_at.present?
  def archive! = update!(archived_at: Time.current)
  def restore! = update!(archived_at: nil)

  def unit_label = unit == "custom" ? custom_unit : UNITS.fetch(unit)

  def duration_label
    return unless duration_minutes

    hours, minutes = duration_minutes.divmod(60)
    [ ("#{hours} h" if hours.positive?), ("#{minutes} min" if minutes.positive?) ].compact.join(" ")
  end

  # A copy with a fresh name; never archived.
  def duplicate
    dup.tap do |copy|
      copy.uid = nil
      copy.name = "#{name} (copy)"
      copy.archived_at = nil
      copy.location_price_inputs = location_prices.includes(:location).to_h { [ _1.location.uid, _1.unit_price.to_s ] } # CAT-08
    end
  end

  # Move within its category: -1 up, +1 down.
  def move!(direction)
    siblings = self.class.active.where(category_id:).ordered.to_a
    index = siblings.index(self) or return
    target = index + direction.to_i.clamp(-1, 1)
    return unless target.between?(0, siblings.size - 1)

    siblings.insert(target, siblings.delete_at(index))
    transaction { siblings.each_with_index { |item, position| item.update_column(:position, position) } }
  end

  # The values a document line copies from this item (QTE-01, INV-01, JOB-01).
  def line_attributes
    { "catalog_item_uid" => uid, "name" => name, "description" => description, "unit" => unit_label,
      "unit_price_cents" => unit_price_cents, "taxable" => taxable }
  end

  # For the item picker.
  private def location_prices_readable
    @location_price_inputs.each do |uid, value|
      next if value.empty?

      cents = Money.parse(value, business.currency_code).cents rescue nil
      errors.add(:base, "The price for #{Location.find_by(uid:)&.name || "a location"} isn't an amount we can read.") if cents.nil? || cents.negative?
    end
  end

  private def save_location_prices
    locations = Location.where(primary: false, uid: @location_price_inputs.keys).index_by(&:uid)
    @location_price_inputs.each do |uid, value|
      location = locations[uid] or next
      if value.empty? then location_prices.where(location:).delete_all
      else # an upsert, so a double submit can't trip the unique index
        LocationPrice.upsert({ business_id:, location_id: location.id, catalog_item_id: id, unit_price_cents: Money.parse(value, business.currency_code).cents },
                             unique_by: %i[location_id catalog_item_id], record_timestamps: true)
      end
    end
    @location_price_inputs = nil
  end

  def as_picker_json(location: nil, overrides: nil)
    price = price_at(location, overrides:)
    { uid:, name:, description:, unit: unit_label, taxable:, category: category&.name,
      price: price&.format, unit_price: price&.to_s, unit_price_cents: price&.cents }
  end
end
