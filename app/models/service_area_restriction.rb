# Geographic exclusions within service areas.
#
# The ServiceAreaRestriction model represents geographic exclusions within
# service areas, allowing businesses to specify cities, states, or zip codes
# where they do not provide services despite being within their service radius.
#
# @attr [Integer] service_area_id Associated service area (foreign key, required)
# @attr [String] restriction_type Type of restriction - 'city', 'state', 'zip_code' (required)
# @attr [String] city Excluded city
# @attr [String] state Excluded state
# @attr [String] zip_code Excluded zip code
# @attr [String] reason Restriction reason
class ServiceAreaRestriction < ApplicationRecord
  # Relationships
  belongs_to :service_area

  # Validations
  validates :service_area_id, presence: true
  validates :restriction_type, presence: true, inclusion: { in: %w[city state zip_code] }
  validates :city, presence: true, if: :city_restriction?
  validates :state, presence: true, if: :state_restriction?
  validates :zip_code, presence: true, if: :zip_code_restriction?

  # Scopes
  scope :by_type, ->(type) { where(restriction_type: type) }
  scope :city_restrictions, -> { where(restriction_type: "city") }
  scope :state_restrictions, -> { where(restriction_type: "state") }
  scope :zip_code_restrictions, -> { where(restriction_type: "zip_code") }

  # Instance methods
  def city_restriction?
    restriction_type == "city"
  end

  def state_restriction?
    restriction_type == "state"
  end

  def zip_code_restriction?
    restriction_type == "zip_code"
  end

  def restricted_location
    case restriction_type
    when "city"
      city
    when "state"
      state
    when "zip_code"
      zip_code
    end
  end

  def display_restriction
    case restriction_type
    when "city"
      "City: #{city}"
    when "state"
      "State: #{state}"
    when "zip_code"
      "Zip Code: #{zip_code}"
    end
  end
end
