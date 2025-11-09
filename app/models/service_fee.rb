# Additional fees for services.
#
# The ServiceFee model represents additional fees for services
# in the Shadetree platform. Each service can have multiple fees
# applied, with support for percentage or fixed fee amounts and
# location-specific fee configurations.
#
# @attr [Integer] service_id Associated service (foreign key, required)
# @attr [String] fee_name Fee name/type (required)
# @attr [Decimal] fee_amount Fee amount percentage or fixed amount (required)
# @attr [String] fee_type Fee calculation type - 'percentage' or 'fixed' (required)
# @attr [Boolean] is_mandatory Mandatory fee flag (default: true)
# @attr [Integer] location_id Location-specific fee (foreign key, optional)
class ServiceFee < ApplicationRecord
  # Relationships
  belongs_to :service
  belongs_to :location, optional: true

  # Validations
  validates :service_id, presence: true
  validates :fee_name, presence: true
  validates :fee_amount, presence: true, numericality: { greater_than: 0 }
  validates :fee_type, presence: true, inclusion: { in: %w[percentage fixed] }
  validates :fee_name, uniqueness: {
    scope: [ :service_id, :location_id ],
    message: "already exists for this service and location combination"
  }
  validate :service_and_location_belong_to_same_business
  validate :percentage_fee_amount_within_bounds

  # Scopes
  scope :percentage_fees, -> { where(fee_type: "percentage") }
  scope :fixed_fees, -> { where(fee_type: "fixed") }
  scope :mandatory_fees, -> { where(is_mandatory: true) }
  scope :optional_fees, -> { where(is_mandatory: false) }
  scope :for_location, ->(location_id) { where(location_id: location_id) }
  scope :global_fees, -> { where(location_id: nil) }
  scope :applicable_to_location, ->(location_id) { where(location_id: [ nil, location_id ]) }

  # Instance methods
  def percentage_fee?
    fee_type == "percentage"
  end

  def fixed_fee?
    fee_type == "fixed"
  end

  def mandatory?
    is_mandatory?
  end

  def optional?
    !is_mandatory?
  end

  def global_fee?
    location_id.nil?
  end

  def location_specific?
    location_id.present?
  end

  def fee_amount_display
    if percentage_fee?
      "#{fee_amount.to_f}%"
    else
      formatted_amount
    end
  end

  def formatted_amount
    service.business.currency == "USD" ? "$#{fee_amount.to_f}" : "#{fee_amount.to_f}"
  end

  def calculate_fee_amount(base_price)
    return 0 if base_price.nil? || base_price <= 0

    case fee_type
    when "percentage"
      base_price * (fee_amount / 100)
    when "fixed"
      fee_amount
    else
      0
    end
  end

  def apply_fee_to_price(base_price)
    return base_price if base_price.nil? || base_price <= 0
    return base_price if optional? # Optional fees are not automatically applied

    fee_charge = calculate_fee_amount(base_price)
    base_price + fee_charge
  end

  def fee_breakdown_for_price(base_price)
    return { base_price: base_price, fee_amount: 0, total_price: base_price } if base_price.nil? || base_price <= 0

    fee_charge = calculate_fee_amount(base_price)

    {
      base_price: base_price,
      fee_amount: fee_charge,
      total_price: base_price + fee_charge
    }
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

  def fee_description
    location_text = location_specific? ? " (#{location.name})" : " (Global)"
    mandatory_text = is_mandatory? ? " (Mandatory)" : " (Optional)"
    "#{fee_name}: #{fee_amount_display}#{location_text}#{mandatory_text}"
  end

  def can_be_deleted?
    # Add logic to check if fee is used in any invoices or transactions
    true # Simplified for now
  end

  def duplicate_for_location(target_location)
    return nil unless target_location.business_id == business.id

    new_fee = self.dup
    new_fee.location = target_location
    new_fee.save
    new_fee
  end

  def update_amount(new_amount)
    self.fee_amount = new_amount
    save
  end

  def make_mandatory!
    update!(is_mandatory: true)
  end

  def make_optional!
    update!(is_mandatory: false)
  end

  def applicable_to_location?(check_location)
    return true if global_fee?
    location_id == check_location&.id
  end

  def fee_impact_on_price(base_price)
    return 0 if base_price.nil? || base_price <= 0 || optional?

    fee_charge = calculate_fee_amount(base_price)
    percentage_impact = (fee_charge / base_price * 100).round(2)

    {
      fee_amount: fee_charge,
      percentage_impact: percentage_impact,
      new_total: base_price + fee_charge
    }
  end

  private

  def service_and_location_belong_to_same_business
    return unless service && location

    if service.business_id != location.business_id
      errors.add(:location, "must belong to the same business as the service")
    end
  end

  def percentage_fee_amount_within_bounds
    return unless percentage_fee?

    if fee_amount < 0 || fee_amount > 100
      errors.add(:fee_amount, "must be between 0 and 100 for percentage fees")
    end
  end
end
