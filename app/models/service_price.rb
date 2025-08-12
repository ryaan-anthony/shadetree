# Location-specific service pricing.
#
# The ServicePrice model represents location-specific service pricing
# for businesses in the Shadetree platform. Each service can have different
# pricing at different locations, with support for effective dates and
# currency settings.
#
# @attr [Integer] service_id Associated service (foreign key, required)
# @attr [Integer] location_id Associated location (foreign key, required)
# @attr [Decimal] base_price Base service price (required)
# @attr [String] currency Price currency (default: 'USD')
# @attr [Date] effective_date Price effective date
# @attr [Date] expires_date Price expiration date
class ServicePrice < ApplicationRecord
  # Relationships
  belongs_to :service
  belongs_to :location

  # Validations
  validates :service_id, presence: true
  validates :location_id, presence: true
  validates :base_price, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP CAD AUD] }
  validates :service_id, uniqueness: { scope: :location_id, message: "already has pricing for this location" }
  validate :effective_date_before_expires_date
  validate :service_and_location_belong_to_same_business

  # Scopes
  scope :active, -> { where(arel_table[:effective_date].lteq(Date.current).or(arel_table[:effective_date].eq(nil))) }
  scope :not_expired, -> { where(arel_table[:expires_date].gteq(Date.current).or(arel_table[:expires_date].eq(nil))) }
  scope :current, -> { active.not_expired }
  scope :for_currency, ->(currency) { where(currency: currency) }
  scope :effective_on, ->(date) { where(arel_table[:effective_date].lteq(date).or(arel_table[:effective_date].eq(nil))) }
  scope :not_expired_on, ->(date) { where(arel_table[:expires_date].gteq(date).or(arel_table[:expires_date].eq(nil))) }
  scope :valid_on, ->(date) { effective_on(date).not_expired_on(date) }

  # Instance methods
  def active?
    return true if effective_date.nil?
    effective_date <= Date.current
  end

  def expired?
    return false if expires_date.nil?
    expires_date < Date.current
  end

  def current?
    active? && !expired?
  end

  def effective_on?(date)
    return true if effective_date.nil?
    effective_date <= date
  end

  def expired_on?(date)
    return false if expires_date.nil?
    expires_date < date
  end

  def valid_on?(date)
    effective_on?(date) && !expired_on?(date)
  end

  def formatted_price
    "$#{base_price.to_f}"
  end

  def price_with_currency
    case currency
    when 'USD'
      "$#{base_price.to_f}"
    when 'EUR'
      "€#{base_price.to_f}"
    when 'GBP'
      "£#{base_price.to_f}"
    when 'CAD'
      "C$#{base_price.to_f}"
    when 'AUD'
      "A$#{base_price.to_f}"
    else
      "#{base_price.to_f} #{currency}"
    end
  end

  def business
    service.business
  end

  def service_name
    service.name
  end

  def location_name
    location.name
  end

  def pricing_period
    start_date = effective_date&.strftime('%m/%d/%Y') || 'Start of time'
    end_date = expires_date&.strftime('%m/%d/%Y') || 'Indefinite'
    "#{start_date} - #{end_date}"
  end

  def days_until_effective
    return 0 if effective_date.nil? || active?
    (effective_date - Date.current).to_i
  end

  def days_until_expiration
    return nil if expires_date.nil?
    return 0 if expired?
    (expires_date - Date.current).to_i
  end

  def clone_for_location(target_location)
    return nil unless target_location.business_id == business.id

    new_price = self.dup
    new_price.location = target_location
    new_price.save
    new_price
  end

  def update_price(new_price, effective_date = nil)
    self.base_price = new_price
    self.effective_date = effective_date if effective_date.present?
    save
  end

  def extend_expiration(new_expires_date)
    return false if new_expires_date && expires_date && new_expires_date <= expires_date

    update(expires_date: new_expires_date)
  end

  def price_change_from(other_price)
    return nil unless other_price.is_a?(ServicePrice)

    change = base_price - other_price.base_price
    percentage_change = ((change / other_price.base_price) * 100).round(2)

    {
      amount_change: change,
      percentage_change: percentage_change,
      direction: change >= 0 ? 'increase' : 'decrease'
    }
  end

  private

  def effective_date_before_expires_date
    return unless effective_date.present? && expires_date.present?

    if effective_date >= expires_date
      errors.add(:expires_date, "must be after the effective date")
    end
  end

  def service_and_location_belong_to_same_business
    return unless service && location

    if service.business_id != location.business_id
      errors.add(:location, "must belong to the same business as the service")
    end
  end
end
