# PAY-08: what an invoice takes off for money billed earlier. Progress billed on a line before it
# was done is credited on that line's final bill ("Billed earlier on INV-0003"), and progress left
# over on work with nothing left to bill (over-billing) on the quote's next invoice. Both come off
# before tax, at the tax rates the progress was charged at, so tax is charged once: the invoice
# prices them as negative lines. PAY-07 adds deposits and take-backs, after tax.
#
# Written under PAY-06's lock (the quote, then the invoice) and worked out again on a draft each
# time it's saved, so a draft is right when it's sent; a sent invoice's credits don't change.
class InvoiceCredit < ApplicationRecord
  include BusinessOwned

  KINDS = %w[progress over_billed].freeze
  PRE_TAX = %w[progress over_billed].freeze

  belongs_to :invoice, inverse_of: :credits
  belongs_to :source_invoice, class_name: "Invoice"
  belongs_to :source_line_item, class_name: "InvoiceLineItem", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }

  before_validation { self.business ||= invoice&.business }

  # Credits that count: on an invoice that went out and isn't void. A draft's are worked out again
  # when it's sent.
  scope :counted, -> { joins(:invoice).where.not(invoices: { sent_at: nil }).where.not(invoices: { status: "void" }) }

  def pre_tax? = PRE_TAX.include?(kind)

  def amount = Money.new(amount_cents, invoice.currency)

  def tax_rate_list = tax_rates.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  # A negative line, so tax is worked out on what's left.
  def to_pricing = Pricing::Line.new(quantity: 1, unit_price: Money.new(-amount_cents, invoice.currency), tax_rates: tax_rate_list, credit: true)

  def label = "#{kind == "progress" ? "Billed earlier" : "Over-billed"} on #{source_invoice.number}"

  # What a revision keeps, so a discarded revision puts the same credits back.
  def snapshot = attributes.slice(*%w[kind source_invoice_id source_line_item_id amount_cents tax_rates position])
end
