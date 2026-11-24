# One line on an invoice (PAY-01): copied from a job or quote, from the catalog, or typed. Shared
# with quote and job lines through DocumentLine; amounts are cents in the invoice's currency.
#
# PAY-06: a line copied from work says what it bills: a job line (and its quote line), or a quote
# line billed directly. `final` marks the line's one final bill; the database refuses a second on
# invoices that aren't void (`invoice_status` follows the invoice's, by a cascading foreign key, and
# is never written here). The links are kept through the builder's autosave, since rows are matched
# by key; a typed line bills nothing.
class InvoiceLineItem < ApplicationRecord
  include BusinessOwned
  include DocumentLine

  belongs_to :invoice, inverse_of: :line_items
  belongs_to :catalog_item, optional: true # set only through catalog_item_id_for, within the business
  belongs_to :job_line_item, optional: true
  belongs_to :quote_line_item, optional: true
  has_one :direct_claim, -> { where(job_id: nil) }, class_name: "JobClaim", inverse_of: :invoice_line_item, dependent: nil

  attr_readonly :invoice_status

  # Final bills that count: on an invoice that isn't void (a draft counts: it holds the line).
  scope :final_bills, -> { where(final: true).where.not(invoice_status: "void") }

  def document_currency = invoice.currency

  # JOB-09: a line removed from a draft frees the quote work it billed directly, before it goes.
  before_destroy { QuoteWork.release_direct!(JobClaim.where(invoice_line_item_id: id)) }

  before_validation { self.business ||= invoice&.business }

  validates :key, presence: true, length: { maximum: 64 }

  # Its job's tax rates when the invoice's jobs differ; otherwise the invoice's.
  def own_tax_rate_list = tax_rates&.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  def to_pricing(rates) = super(own_tax_rate_list || rates)

  # What the revision record keeps, so a discarded revision puts the same line back.
  def links = { "key" => key, "job_line_item_id" => job_line_item_id, "quote_line_item_id" => quote_line_item_id, "final" => final, "tax_rates" => tax_rates }
end
