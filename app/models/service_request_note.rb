# An internal note on a request (CLI-04). Clients never see these.
class ServiceRequestNote < ApplicationRecord
  include BusinessOwned
  belongs_to_business_record :service_request
  belongs_to :user, optional: true

  normalizes :body, with: ->(value) { value.to_s.strip }
  validates :body, presence: { message: "can't be empty" }, length: { maximum: 5_000 }
end
