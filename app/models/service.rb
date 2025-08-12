# Individual services offered by the business.
#
# The Service model represents individual services offered by businesses
# in the Shadetree platform. Each service belongs to a business and service
# category, with configuration for duration, location requirements, and
# pricing structures.
#
# @attr [Integer] business_id Associated business (foreign key, required)
# @attr [Integer] service_category_id Service category (foreign key, required)
# @attr [String] name Service name (required)
# @attr [String] description Service description
# @attr [Integer] duration Service duration in minutes (required)
# @attr [Boolean] requires_location Location requirement (default: false)
# @attr [Boolean] is_active Service status (default: true)
# @attr [Integer] sort_order Display order (default: 0)
class Service < ApplicationRecord
  # Relationships
  belongs_to :business
  belongs_to :service_category
  has_many :service_prices, dependent: :destroy
  has_many :service_taxes, dependent: :destroy
  has_many :service_fees, dependent: :destroy
  has_many :service_requirements, dependent: :destroy
  has_many :pricing_tiers, dependent: :destroy
  has_many :staff_service_assignments, dependent: :destroy
  has_many :staff_members, through: :staff_service_assignments
  has_many :package_services, dependent: :destroy
  has_many :service_packages, through: :package_services

  # Validations
  validates :business_id, presence: true
  validates :service_category_id, presence: true
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id, message: "already exists for this business" }
  validates :duration, presence: true, numericality: { greater_than: 0 }
  validates :sort_order, numericality: { greater_than_or_equal_to: 0 }
  validate :category_must_belong_to_same_business

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :ordered, -> { order(:sort_order, :name) }
  scope :for_business, ->(business_id) { where(business_id: business_id) }
  scope :in_category, ->(category_id) { where(service_category_id: category_id) }
  scope :requires_location, -> { where(requires_location: true) }
  scope :location_flexible, -> { where(requires_location: false) }

  # Instance methods
  def active?
    is_active?
  end

  def inactive?
    !is_active?
  end

  def duration_hours
    duration / 60.0
  end

  def duration_display
    hours = duration / 60
    minutes = duration % 60

    if hours > 0 && minutes > 0
      "#{hours}h #{minutes}m"
    elsif hours > 0
      "#{hours}h"
    else
      "#{minutes}m"
    end
  end

  def category_path
    service_category.full_name
  end

  def full_name
    "#{category_path} > #{name}"
  end

  def base_price_for_location(location)
    service_prices.find_by(location: location)&.base_price
  end

  def price_range
    prices = service_prices.pluck(:base_price)
    return "No pricing set" if prices.empty?

    min_price = prices.min
    max_price = prices.max

    if min_price == max_price
      "$#{min_price}"
    else
      "$#{min_price} - $#{max_price}"
    end
  end

  def available_at_location?(location)
    return true unless requires_location?
    service_prices.exists?(location: location)
  end

  def assigned_staff_count
    staff_members.active.count
  end

  def has_assigned_staff?
    staff_service_assignments.exists?
  end

  def total_taxes_for_location(location)
    service_taxes.where(location: [nil, location]).sum do |tax|
      next 0 unless base_price = base_price_for_location(location)

      case tax.tax_type
      when 'percentage'
        base_price * (tax.tax_rate / 100)
      when 'fixed'
        tax.tax_rate
      else
        0
      end
    end
  end

  def total_fees_for_location(location)
    service_fees.where(location: [nil, location], is_mandatory: true).sum do |fee|
      next 0 unless base_price = base_price_for_location(location)

      case fee.fee_type
      when 'percentage'
        base_price * (fee.fee_amount / 100)
      when 'fixed'
        fee.fee_amount
      else
        0
      end
    end
  end

  def total_price_for_location(location)
    base_price = base_price_for_location(location)
    return nil unless base_price

    base_price + total_taxes_for_location(location) + total_fees_for_location(location)
  end

  def has_pricing_tiers?
    pricing_tiers.exists?
  end

  def requirements_summary
    service_requirements.mandatory.pluck(:description)
  end

  def can_be_deleted?
    # Check if service is used in any bookings, packages, etc.
    !package_services.exists? # Add more conditions as needed
  end

  def deactivate!
    update!(is_active: false)
  end

  def activate!
    update!(is_active: true)
    # Activate category if it's inactive
    service_category.activate! if service_category.inactive?
  end

  def duplicate_for_category(target_category)
    return nil unless target_category.business_id == business_id

    new_service = self.dup
    new_service.service_category = target_category
    new_service.name = "#{name} (Copy)"
    new_service.save

    # Duplicate related records
    service_prices.each { |price| price.dup.update(service: new_service) }
    service_taxes.each { |tax| tax.dup.update(service: new_service) }
    service_fees.each { |fee| fee.dup.update(service: new_service) }
    service_requirements.each { |req| req.dup.update(service: new_service) }
    pricing_tiers.each { |tier| tier.dup.update(service: new_service) }

    new_service
  end

  private

  def category_must_belong_to_same_business
    return unless service_category_id.present?

    if service_category && service_category.business_id != business_id
      errors.add(:service_category, "must belong to the same business")
    end
  end
end
