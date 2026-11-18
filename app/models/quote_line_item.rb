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
end
