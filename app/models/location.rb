# Physical business locations and service points.
#
# The Location model represents physical business locations and service points
# for businesses in the Shadetree platform. Each location belongs to a business
# and can have specific operating hours, service areas, and contact information.
#
# @attr [Integer] business_id Associated business (foreign key, required)
# @attr [String] name Location name (required)
# @attr [String] timezone Location timezone
# @attr [String] address Street address (required)
# @attr [String] city City (required)
# @attr [String] state State/Province (required)
# @attr [String] zip_code Postal code (required)
# @attr [Decimal] latitude GPS latitude (precision: 10, scale: 6)
# @attr [Decimal] longitude GPS longitude (precision: 10, scale: 6)
# @attr [Boolean] is_primary Primary location flag (default: false)
# @attr [String] phone Location-specific phone
# @attr [String] email Location-specific email
# @attr [Boolean] active Location status (default: true)
class Location < ApplicationRecord
  # Relationships
  belongs_to :business
  has_many :service_areas, dependent: :destroy
  has_many :operating_hours, dependent: :destroy
  has_many :business_closures, dependent: :destroy
  has_many :special_availabilities, dependent: :destroy
  has_many :service_prices, dependent: :destroy

  # Validations
  validates :business_id, presence: true
  validates :name, presence: true
  validates :address, presence: true
  validates :city, presence: true
  validates :state, presence: true
  validates :zip_code, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_blank: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :primary, -> { where(is_primary: true) }

  # Callbacks
  before_save :ensure_single_primary_location

  # Instance methods
  def full_address
    [address, city, state, zip_code].compact.join(', ')
  end

  def coordinates
    return nil unless latitude.present? && longitude.present?
    [latitude, longitude]
  end

  def has_coordinates?
    latitude.present? && longitude.present?
  end

  def contact_phone
    phone.presence || business.phone
  end

  def contact_email
    email.presence || business.email
  end

  private

  def ensure_single_primary_location
    if is_primary? && is_primary_changed?
      # Set all other locations for this business to not primary
      Location.where(business: business).where.not(id: id).update_all(is_primary: false)
    end
  end
end
