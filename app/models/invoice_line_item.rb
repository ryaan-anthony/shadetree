# One line on an invoice (PAY-01): copied from a job or quote, from the catalog, or typed. Shared
# with quote and job lines through DocumentLine; amounts are cents in the invoice's currency.
class InvoiceLineItem < ApplicationRecord
  include BusinessOwned
  include DocumentLine

  belongs_to :invoice, inverse_of: :line_items
  belongs_to :catalog_item, optional: true # set only through catalog_item_id_for, within the business

  def document_currency = invoice.currency

  # JOB-09: a line removed from a draft frees the quote work it billed directly (PAY-06 takes this over).
  before_destroy { QuoteWork.release_direct!(JobClaim.where(invoice_line_item_id: id)) }

  before_validation { self.business ||= invoice&.business }

  validates :key, presence: true, length: { maximum: 64 }
end
