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

  # Direct billing (a quote line's final bill with no job) is a claim with no job (JOB-09): made
  # with the line, following its quantity on a draft, and freed before the line goes.
  after_create(if: :direct?) { QuoteWork.claim_direct!(self) }
  after_update(if: -> { saved_change_to_quantity? && direct_claim }) { QuoteWork.follow_direct!(direct_claim, quantity) }
  before_destroy { QuoteWork.release_direct!(JobClaim.where(invoice_line_item_id: id)) }

  def direct? = final && quote_line_item_id && job_line_item_id.nil?

  before_validation { self.business ||= invoice&.business }

  validates :key, presence: true, length: { maximum: 64 }

  # Its job's tax rates when the invoice's jobs differ; otherwise the invoice's.
  def own_tax_rate_list = tax_rates&.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  # PAY-08: its share of its quote line's fixed discount comes off it too.
  def to_pricing(rates) = super(own_tax_rate_list || rates).with(share: (Money.new(discount_share_cents, document_currency) if discount_share_cents.to_i.positive?))

  # What the revision record keeps, so a discarded revision puts the same line back.
  def links = { "key" => key, "job_line_item_id" => job_line_item_id, "quote_line_item_id" => quote_line_item_id, "final" => final, "tax_rates" => tax_rates, "discount_share_cents" => discount_share_cents }
end
