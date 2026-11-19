# Staff actions on a quote that nothing else records (QTE-06), for its activity history:
# archived, unarchived, expiry_extended ({ "from", "to" }), duplicated ({ "from" => number }),
# revised ({ "revision" }), repriced ({ "location", "changed" }, CAT-08). Sends, views and client responses have their own records.
class QuoteEvent < ApplicationRecord
  include BusinessOwned

  KINDS = %w[archived unarchived expiry_extended duplicated revised repriced].freeze

  belongs_to_business_record :quote
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(quote, kind, by:, **data)
    create!(business: quote.business, quote:, kind: kind.to_s, user: by, data:, occurred_at: Time.current)
  end
end
