# One line on a quote (QTE-01): a copy of a catalog item or a custom line. Amounts are cents
# in the quote's currency; Pricing::Line does the arithmetic. Shared with job lines through
# DocumentLine.
class QuoteLineItem < ApplicationRecord
  include BusinessOwned
  include DocumentLine

  belongs_to :quote, inverse_of: :line_items
  belongs_to :catalog_item, optional: true # set only through catalog_item_id_for, within the business

  def document_currency = quote.currency

  before_validation { self.business ||= quote&.business }

  validates :key, presence: true, length: { maximum: 64 }

  # QTE-08: what the catalog charged for the line's service, at the quote's location, when the
  # line was added (or its service changed): the price it was added at, so a later price list
  # change is told apart from a price typed in.
  before_validation(if: -> { new_record? || will_save_change_to_catalog_item_id? }) do
    self.catalog_price_cents = catalog_item&.price_at(quote&.location)&.cents
  end
end
