# An invoice for a client (PAY-01): made from a job (its items), from an approved quote, or from
# scratch. It prices exactly like a quote (PricedDocument, BuiltDocument and DocumentLine are
# shared, PLT-08) and adds what billing needs: an issue date, payment terms and the due date
# they give, and the amount paid so far.
#
# Statuses: draft → sent (PAY-02) → partially_paid → paid (payments, PAY-04/PAY-05), or void.
# Overdue isn't a status: it's a sent or partly paid invoice whose due date has passed, for the
# business's today. Each change of status is recorded as an InvoiceEvent.
class Invoice < ApplicationRecord
  include BusinessOwned
  include PricedDocument
  include BuiltDocument

  STATUSES = %w[draft sent partially_paid paid void].freeze
  STATUS_LABELS = { "draft" => "Draft", "sent" => "Sent", "partially_paid" => "Partly paid", "paid" => "Paid", "void" => "Void" }.freeze
  # Unpaid and not void: what the business is still owed.
  OUTSTANDING = %w[sent partially_paid].freeze

  # Payment terms and the days they give; "custom" is a due date chosen on the invoice.
  TERMS = { "due_on_receipt" => 0, "net_7" => 7, "net_15" => 15, "net_30" => 30, "custom" => nil }.freeze
  TERM_LABELS = { "due_on_receipt" => "Due on receipt", "net_7" => "Net 7", "net_15" => "Net 15", "net_30" => "Net 30",
                  "custom" => "Custom date" }.freeze

  belongs_to_business_record :client
  belongs_to_business_record :property, optional: true
  belongs_to_business_record :job, optional: true
  belongs_to_business_record :quote, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :sent_by, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
  has_many :line_items, -> { order(:position, :id) }, class_name: "InvoiceLineItem", inverse_of: :invoice,
           dependent: :delete_all, autosave: true
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "InvoiceEvent", inverse_of: :invoice, dependent: :delete_all

  normalizes :title, with: ->(value) { value.to_s.squish.presence }
  normalizes :message, :internal_notes, :terms, with: ->(value) { value.to_s.strip.presence }

  validates :number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_terms, inclusion: { in: TERMS.keys }
  validates :issued_on, :due_on, presence: true
  validates :title, length: { maximum: 120 }
  validates :message, :terms, :internal_notes, length: { maximum: 5_000 }
  validate { errors.add(:due_on, "can't be before the issue date") if due_on && issued_on && due_on < issued_on }
  validate :belongs_with_client

  # Prices copied or typed into a new invoice's lines need its currency before it's saved.
  after_initialize { self.currency ||= (business || Current.business)&.currency_code if new_record? }
  before_validation :assign_number_and_defaults, on: :create
  before_validation :apply_payment_terms

  # A new draft for a client, with the business's defaults (terms, due date, taxes).
  def self.start(client:, property: nil, created_by: nil)
    create!(client:, property: property || client.primary_property, created_by:).tap { _1.record!(:created, by: created_by) }
  end

  # PAY-01: the job's work, billed: its client, property, items, discount and taxes. The job's
  # quote (if any) is linked too. A job can be invoiced more than once (progress billing).
  def self.from_job!(job, by: nil)
    transaction do
      invoice = new(client: job.client, property: job.property, job:, quote: job.quote, created_by: by, title: job.title)
      invoice.copy_pricing_from(job)
      invoice.save!
      invoice.record!(:created, by:, from: "job", number: job.number)
      invoice
    end
  end

  # PAY-01: an approved quote, billed as agreed (the quote's lines, not the job's on-site
  # changes). Its job is linked when there is one.
  def self.from_quote!(quote, by: nil)
    raise ArgumentError, "Only an approved quote can be invoiced." unless quote.approved?

    transaction do
      invoice = new(client: quote.client, property: quote.property, quote:, job: quote.job, created_by: by, title: quote.title)
      invoice.copy_pricing_from(quote)
      invoice.save!
      invoice.record!(:created, by:, from: "quote", number: quote.number)
      invoice
    end
  end

  def copy_pricing_from(document)
    assign_attributes(tax_rates: document.tax_rates, prices_include_tax: document.prices_include_tax,
                      discount_kind: document.discount_kind, discount_percent: document.discount_percent,
                      discount_amount_cents: document.discount_amount_cents)
    sync_line_items(BuiltDocument.rows_from(document.current_line_items))
  end

  def draft? = status == "draft"
  def void? = status == "void"
  def paid? = status == "paid"
  def status_label = STATUS_LABELS.fetch(status)
  def terms_label = TERM_LABELS.fetch(payment_terms)

  # Drafts are edited freely. A sent invoice changes only by revision (part 2); once anything
  # is paid, its items can't change at all.
  def editable? = draft?
  def payments? = amount_paid_cents.positive?

  def outstanding? = OUTSTANDING.include?(status)
  def overdue?(today = business.today) = outstanding? && due_on < today

  def amount_paid = Money.new(amount_paid_cents, currency)
  def balance = Money.new([ total_cents - amount_paid_cents, 0 ].max, currency)

  # The due date a choice of terms gives, from the issue date ("custom" keeps the one chosen).
  def due_on_for(terms, issued = issued_on)
    days = TERMS[terms]
    days && issued ? issued + days : due_on
  end

  # A draft that was never sent can be deleted; anything sent is voided instead (part 2).
  def deletable? = draft? && sent_at.nil?

  def record!(kind, by: nil, **data) = InvoiceEvent.record!(self, kind, by:, **data)

  # By invoice number, or by client (name, phone, email or address, as CLI-02 searches).
  def self.search(query)
    query = query.to_s.strip
    return all if query.empty?

    where("invoices.number ILIKE ?", "%#{sanitize_sql_like(query)}%").or(where(client_id: Client.search(query).select(:id)))
  end

  private

  def assign_number_and_defaults
    return unless business

    self.number ||= business.next_document_number(:invoice)
    self.currency ||= business.currency_code
    self.issued_on ||= business.today
    self.terms ||= business.invoice_terms
    self.tax_rate_list = TaxRate.for_new_document(client:) if tax_rates.blank? && job.nil? && quote.nil?
    return if payment_terms_changed? # chosen

    days = business.invoice_due_days.to_i
    self.payment_terms = TERMS.key(days) || "custom"
    self.due_on ||= issued_on + days
  end

  # Terms other than "custom" set the due date from the issue date.
  def apply_payment_terms
    self.due_on = due_on_for(payment_terms) if TERMS[payment_terms] && issued_on
  end

  def belongs_with_client
    return unless client

    errors.add(:property, "must be one of this client's properties") if property && property.client_id != client_id
    errors.add(:job, "must be for the same client") if job && job.client_id != client_id
    errors.add(:quote, "must be for the same client") if quote && quote.client_id != client_id
  end
end
