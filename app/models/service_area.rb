# Service delivery territories for each location.
#
# The ServiceArea model represents geographic service territories for business
# locations. Service areas are defined as radius-based coverage from the location,
# allowing businesses to specify where they provide services.
#
# @attr [Integer] location_id Associated location (foreign key, required)
# @attr [Decimal] radius Service radius in miles/km
# @attr [Boolean] active Service area status (default: true)
class ServiceArea < ApplicationRecord
  # Relationships
  belongs_to :location
  has_many :service_area_restrictions, dependent: :destroy

  # Validations
  validates :location_id, presence: true
  validates :radius, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :active, -> { where(active: true) }

  # Instance methods
  def coverage_description
    "#{radius} mile radius"
  end
end
