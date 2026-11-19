# A named sales tax a business charges, e.g. "State 6.25%" (CAT-04). Rates marked
# applies_by_default form the set new documents apply to taxable lines; a document can
# change its own set, and a tax-exempt client starts with none.
#
# Documents never point at these rows: they copy #to_pricing (name and percent) when
# created, so editing or archiving a rate leaves existing quotes and invoices unchanged.
class TaxRate < ApplicationRecord
  include BusinessOwned

  MAX_ACTIVE = 10

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true, length: { maximum: 40 }
  validates :percent, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validate :percent_has_at_most_four_decimals
  validate :name_unique_among_active, if: -> { archived_at.nil? && (new_record? || will_save_change_to_name? || will_save_change_to_archived_at?) }
  validate :within_active_limit, if: -> { archived_at.nil? && (new_record? || will_save_change_to_archived_at?) }

  # The name and limit checks read other rows, so saves of an active rate take a lock on the
  # business row first (validation runs inside the save transaction): two submits at once
  # can't both pass. The unique index is the backstop for anything that still collides.
  before_validation :lock_business, if: -> { archived_at.nil? && business_id }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :default_set, -> { active.where(applies_by_default: true).ordered }

  before_create { self.position = (self.class.maximum(:position) || -1) + 1 }

  # The rates a new document applies to its taxable lines.
  def self.for_new_document(client: nil, location: nil)
    return [] if client&.tax_exempt

    (location ? location.default_tax_rates : default_set).map(&:to_pricing)
  end

  def archived? = archived_at.present?
  def archive! = update!(archived_at: Time.current)
  def restore! = update!(archived_at: nil)

  def to_pricing = Pricing::TaxRate.new(name:, percent:)

  # "6.25%": trailing zeros dropped, never scientific notation.
  def percent_label
    return "" if percent.nil?

    "#{percent.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")}%"
  end

  def label = "#{name} #{percent_label}"

  private

  def lock_business = Business.where(id: business_id).lock.pluck(:id)

  def create_or_update(...)
    super
  rescue ActiveRecord::RecordNotUnique
    errors.add(:name, "is already used by another tax rate")
    false
  end

  def percent_has_at_most_four_decimals
    # The column keeps 4 decimals and would silently round more, so reject them as typed.
    raw = percent_before_type_cast
    return unless raw.is_a?(String) && raw.strip.match?(/\A\d*\.\d{5,}\z/)

    errors.add(:percent, "can have at most 4 decimal places")
  end

  def name_unique_among_active
    taken = self.class.active.where("lower(name) = ?", name.to_s.downcase).where.not(id:).exists?
    errors.add(:name, "is already used by another tax rate") if taken
  end

  def within_active_limit
    errors.add(:base, "You can have up to #{MAX_ACTIVE} tax rates. Archive one you no longer use.") if self.class.active.where.not(id:).count >= MAX_ACTIVE
  end
end
