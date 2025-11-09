# Tax configuration for services.
#
# The ServiceTax model represents tax configuration for services
# in the Shadetree platform. Each service can have multiple taxes
# applied, with support for percentage or fixed tax rates and
# location-specific tax configurations.
#
# @attr [Integer] service_id Associated service (foreign key, required)
# @attr [String] tax_name Tax name/type (required)
# @attr [Decimal] tax_rate Tax rate percentage or fixed amount (required)
# @attr [String] tax_type Tax calculation type - 'percentage' or 'fixed' (required)
# @attr [Boolean] is_inclusive Tax inclusion flag (default: false)
# @attr [Integer] location_id Location-specific tax (foreign key, optional)
class ServiceTax < ApplicationRecord
  # Relationships
  belongs_to :service
  belongs_to :location, optional: true

  # Validations
  validates :service_id, presence: true
  validates :tax_name, presence: true
  validates :tax_rate, presence: true, numericality: { greater_than: 0 }
  validates :tax_type, presence: true, inclusion: { in: %w[percentage fixed] }
  validates :tax_name, uniqueness: {
    scope: [ :service_id, :location_id ],
    message: "already exists for this service and location combination"
  }
  validate :service_and_location_belong_to_same_business
  validate :percentage_tax_rate_within_bounds

  # Scopes
  scope :percentage_taxes, -> { where(tax_type: "percentage") }
  scope :fixed_taxes, -> { where(tax_type: "fixed") }
  scope :inclusive_taxes, -> { where(is_inclusive: true) }
  scope :exclusive_taxes, -> { where(is_inclusive: false) }
  scope :for_location, ->(location_id) { where(location_id: location_id) }
  scope :global_taxes, -> { where(location_id: nil) }
  scope :applicable_to_location, ->(location_id) { where(location_id: [ nil, location_id ]) }

  # Instance methods
  def percentage_tax?
    tax_type == "percentage"
  end

  def fixed_tax?
    tax_type == "fixed"
  end

  def inclusive?
    is_inclusive?
  end

  def exclusive?
    !is_inclusive?
  end

  def global_tax?
    location_id.nil?
  end

  def location_specific?
    location_id.present?
  end

  def tax_rate_display
    if percentage_tax?
      "#{tax_rate.to_f}%"
    else
      formatted_rate
    end
  end

  def formatted_rate
    service.business.currency == "USD" ? "$#{tax_rate.to_f}" : "#{tax_rate.to_f}"
  end

  def calculate_tax_amount(base_price)
    return 0 if base_price.nil? || base_price <= 0

    case tax_type
    when "percentage"
      base_price * (tax_rate / 100)
    when "fixed"
      tax_rate
    else
      0
    end
  end

  def effective_price_with_tax(base_price)
    return base_price if base_price.nil? || base_price <= 0

    tax_amount = calculate_tax_amount(base_price)

    if is_inclusive?
      # Tax is already included in the base price
      base_price
    else
      # Tax is added to the base price
      base_price + tax_amount
    end
  end

  def tax_breakdown_for_price(base_price)
    return { base_price: base_price, tax_amount: 0, total_price: base_price } if base_price.nil? || base_price <= 0

    tax_amount = calculate_tax_amount(base_price)

    if is_inclusive?
      # Calculate the base price without tax
      if percentage_tax?
        base_without_tax = base_price / (1 + (tax_rate / 100))
        actual_tax = base_price - base_without_tax
      else
        base_without_tax = base_price - tax_rate
        actual_tax = tax_rate
      end

      {
        base_price: base_without_tax,
        tax_amount: actual_tax,
        total_price: base_price
      }
    else
      {
        base_price: base_price,
        tax_amount: tax_amount,
        total_price: base_price + tax_amount
      }
    end
  end

  def business
    service.business
  end

  def service_name
    service.name
  end

  def location_name
    location&.name || "All locations"
  end

  def tax_description
    location_text = location_specific? ? " (#{location.name})" : " (Global)"
    inclusion_text = is_inclusive? ? " (Inclusive)" : " (Exclusive)"
    "#{tax_name}: #{tax_rate_display}#{location_text}#{inclusion_text}"
  end

  def can_be_deleted?
    # Add logic to check if tax is used in any invoices or transactions
    true # Simplified for now
  end

  def duplicate_for_location(target_location)
    return nil unless target_location.business_id == business.id

    new_tax = self.dup
    new_tax.location = target_location
    new_tax.save
    new_tax
  end

  def update_rate(new_rate)
    self.tax_rate = new_rate
    save
  end

  def applicable_to_location?(check_location)
    return true if global_tax?
    location_id == check_location&.id
  end

  private

  def service_and_location_belong_to_same_business
    return unless service && location

    if service.business_id != location.business_id
      errors.add(:location, "must belong to the same business as the service")
    end
  end

  def percentage_tax_rate_within_bounds
    return unless percentage_tax?

    if tax_rate < 0 || tax_rate > 100
      errors.add(:tax_rate, "must be between 0 and 100 for percentage taxes")
    end
  end
end
