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

  normalizes :name, with: ->(name) { name.to_s.squish }
  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }
  validates :unit, inclusion: { in: UNITS.keys }
  validates :custom_unit, presence: true, length: { maximum: 20 }, if: -> { unit == "custom" }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
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
  def as_picker_json
    { uid:, name:, description:, unit: unit_label, taxable:, category: category&.name,
      price: unit_price&.format, unit_price_cents: }
  end
end
