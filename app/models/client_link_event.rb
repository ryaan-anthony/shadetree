# What happened on a client link: views, one-time actions (approve, pay) and fresh-link requests.
class ClientLinkEvent < ApplicationRecord
  include BusinessOwned

  belongs_to :client_link

  validates :kind, presence: true
end
