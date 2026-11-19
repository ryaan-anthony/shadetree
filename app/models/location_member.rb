# CAT-07: a team member who works at a location. A member can work at several; their default
# location (BusinessUser#default_location) is where documents they create start.
class LocationMember < ApplicationRecord
  include BusinessOwned

  belongs_to_business_record :location
  belongs_to :user

  validates :user_id, uniqueness: { scope: :location_id }
end
