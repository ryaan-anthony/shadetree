# Who has opened a request, and when they last did (CLI-04).
class ServiceRequestView < ApplicationRecord
  include BusinessOwned
  belongs_to_business_record :service_request
  belongs_to :user
end
