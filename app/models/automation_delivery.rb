# NTF-04: an automated template a client got about a document: never the same one twice.
class AutomationDelivery < ApplicationRecord
  include BusinessOwned

  belongs_to :message_template
  belongs_to :subject, polymorphic: true
end
