# A place a client has work done: a service address with access notes (CLI-01). Quotes, jobs
# and visits are for a client at a property. One property per client may be the billing address.
class Property < ApplicationRecord
  include BusinessOwned

  ADDRESS_FIELDS = %w[address_line1 address_line2 city region postal_code].freeze

  belongs_to :client, inverse_of: :properties

  normalizes :label, :address_line1, :address_line2, :city, :region, :postal_code, with: ->(value) { value.to_s.squish.presence }
  normalizes :country, with: ->(value) { value.to_s.strip.upcase.presence }

  # Keep the client's search digest current when this changes on its own (CLI-02).
  after_commit { client&.refresh_search_text! unless destroyed_by_association }

  before_validation { self.business ||= client&.business }

  validates :address_line1, presence: true, length: { maximum: 120 }
  validates :address_line2, :city, :region, length: { maximum: 120 }
  validates :postal_code, length: { maximum: 20 }
  validates :label, length: { maximum: 60 }
  validates :access_notes, length: { maximum: 2_000 }
  validates :country, format: { with: /\A[A-Z]{2}\z/, message: "must be a two-letter country code" }

  def address_lines
    locality = [ city, [ region, postal_code ].compact.join(" ").presence ].compact.join(", ")
    [ address_line1, address_line2, locality.presence ].compact
  end

  def one_line = address_lines.join(", ")
  def name = label.presence || address_line1
end
