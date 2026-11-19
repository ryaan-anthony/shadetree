# INS-02: a business's data, downloadable at any time on any plan. Each download is logged
# here (who, what, when); a full-account export (part 2) is built in the background.
class DataExport < ApplicationRecord
  include BusinessOwned

  STATUSES = %w[building ready failed expired].freeze

  belongs_to :requested_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: ->(_) { TABLES.keys + %w[full] } }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  money = Table.method(:money)
  name_of = ->(user) { user&.full_name }
  # "State 6.25%: 15.00; County 1%: 2.40", from the document's own tax calculation.
  taxes_of = ->(doc) { doc.totals.taxes.map { "#{_1.rate.name} #{_1.rate.percent.to_d.to_s("F").delete_suffix(".0")}%: #{_1.amount}" } }
  line_total = ->(item, currency) { Pricing::DocumentTotals.new(currency:, lines: [ item.to_pricing([]) ]).lines.first.then { [ _1.discount.to_s, _1.subtotal.to_s ] } }
  lines = lambda do |parent_name, number_header|
    proc do
      column(number_header) { _1.public_send(parent_name).number }
      column("Position", number: true, &:position)
      column("Item", &:name)
      column("Description", &:description)
      column("Quantity", number: true) { _1.quantity&.to_s("F") }
      column("Unit", &:unit)
      column("Unit price", number: true) { money.(_1.unit_price_cents, _1.public_send(parent_name).currency) }
      column("Taxable", &:taxable)
      column("Line discount", number: true) { line_total.(_1, _1.public_send(parent_name).currency).first }
      column("Line total", number: true) { line_total.(_1, _1.public_send(parent_name).currency).last }
    end
  end
  notes = lambda do |parent_header, &parent|
    proc do
      column(parent_header, &parent)
      column("Written", &:created_at)
      column("By") { name_of.(_1.user) }
      column("Note", &:body)
    end
  end

  TABLES = [
    Table.new("clients", "Clients", "One row per client, with their emails and phones.", scope: -> { Client.includes(:contact_methods) }) do
      column("Client ID", &:uid)
      column("Name", &:display_name)
      column("Company", &:company_name)
      column("Emails") { |c| c.contact_methods.select(&:email?).map(&:value) }
      column("Phones") { |c| c.contact_methods.select(&:phone?).map(&:value) }
      column("Tags", &:tags)
      column("Tax exempt", &:tax_exempt)
      column("Notes", &:notes)
      column("Archived at", &:archived_at)
      column("Created", &:created_at)
    end,
    Table.new("properties", "Properties", "Client addresses; one client can have several.", scope: -> { Property.includes(:client) }, cursor: %i[client_id position id]) do
      column("Property ID", &:uid)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Label", &:label)
      column("Address line 1", &:address_line1)
      column("Address line 2", &:address_line2)
      column("City", &:city)
      column("State / province", &:region)
      column("Postal code", &:postal_code)
      column("Country", &:country)
      column("Billing address", &:billing)
      column("Access notes", &:access_notes)
    end,
    Table.new("requests", "Requests", "Requests for work from your form or added by your team.", scope: -> { ServiceRequest.includes(:client, :property) }) do
      column("Request ID", &:uid)
      column("Received", &:created_at)
      column("Status", &:status)
      column("Source", &:source)
      column("Client ID") { _1.client&.uid }
      column("Client") { _1.client&.display_name }
      column("Contact name", &:contact_name)
      column("Contact email", &:contact_email)
      column("Contact phone", &:contact_phone)
      column("Services") { |r| Array(r.services).map { _1.is_a?(Hash) ? _1["name"] : _1 } }
      column("Timing", &:timing)
      column("Description", &:description)
      column("Property ID") { _1.property&.uid }
      column("Address given") { |r| r.address.is_a?(Hash) ? r.address.values_at("address_line1", "address_line2", "city", "region", "postal_code").compact_blank.join(", ") : nil }
    end,
    Table.new("quotes", "Quotes", "One row per quote, with its totals and taxes.", scope: -> { Quote.includes(:client, :property, :created_by, :line_items) }) do
      column("Quote number", &:number)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Title", &:title)
      column("Status", &:status)
      column("Currency", &:currency)
      column("Subtotal", number: true) { money.(_1.subtotal_cents, _1.currency) }
      column("Discount", number: true) { money.(_1.discount_total_cents, _1.currency) }
      column("Tax", number: true) { money.(_1.tax_cents, _1.currency) }
      column("Total", number: true) { money.(_1.total_cents, _1.currency) }
      column("Expires", &:expires_on)
      column("Sent", &:sent_at)
      column("Created", &:created_at)
      column("Created by") { name_of.(_1.created_by) }
      column("Property ID") { _1.property&.uid }
      column("Taxes") { taxes_of.(_1) }
      column("Prices include tax", &:prices_include_tax)
      column("Internal notes", &:internal_notes)
    end,
    Table.new("quote_lines", "Quote line items", "Each line on each quote.", scope: -> { QuoteLineItem.includes(:quote) }, cursor: %i[quote_id position id], &lines.("quote", "Quote number")),
    Table.new("jobs", "Jobs", "One row per job, with its totals.", scope: -> { Job.includes(:client, :property, :quote, :line_items) }) do
      column("Job number", &:number)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Title", &:title)
      column("Status", &:status)
      column("From quote") { _1.quote&.number }
      column("Currency", &:currency)
      column("Total", number: true) { money.(_1.total_cents, _1.currency) }
      column("Created", &:created_at)
      column("Completed", &:completed_at)
      column("Cancelled", &:cancelled_at)
      column("Cancel reason", &:cancel_reason)
      column("Property ID") { _1.property&.uid }
      column("Subtotal", number: true) { money.(_1.subtotal_cents, _1.currency) }
      column("Discount", number: true) { money.(_1.discount_total_cents, _1.currency) }
      column("Tax", number: true) { money.(_1.tax_cents, _1.currency) }
      column("Taxes") { taxes_of.(_1) }
      column("Instructions", &:instructions)
      column("Internal notes", &:internal_notes)
    end,
    Table.new("job_lines", "Job line items", "Each line on each job.", scope: -> { JobLineItem.includes(:job) }, cursor: %i[job_id position id], &lines.("job", "Job number")),
    Table.new("visits", "Visits", "Each scheduled visit, by date, with who was on it.", scope: -> { Visit.includes(:assignees, job: :client) }, cursor: %i[scheduled_on id]) do
      column("Visit ID", &:uid)
      column("Job number") { _1.job.number }
      column("Date", &:scheduled_on)
      column("Timing", &:timing)
      column("Starts", &:starts_at)
      column("Duration (minutes)", number: true, &:duration_minutes)
      column("Status", &:status)
      column("Crew") { |v| v.assignees.map(&:full_name) }
      column("Instructions", &:instructions)
      column("Completed", &:completed_at)
      column("Window ends", &:window_ends_at)
      column("Client") { _1.job.client.display_name }
      column("Cancelled", &:cancelled_at)
      column("Cancel reason", &:cancel_reason)
    end,
    Table.new("invoices", "Invoices", "One row per invoice, with totals, taxes and what's been paid.", scope: -> { Invoice.includes(:client, :property, :job, :line_items) }) do
      column("Invoice number", &:number)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Title", &:title)
      column("Status", &:status)
      column("From job") { _1.job&.number }
      column("Currency", &:currency)
      column("Subtotal", number: true) { money.(_1.subtotal_cents, _1.currency) }
      column("Discount", number: true) { money.(_1.discount_total_cents, _1.currency) }
      column("Tax", number: true) { money.(_1.tax_cents, _1.currency) }
      column("Total", number: true) { money.(_1.total_cents, _1.currency) }
      column("Paid", number: true) { money.(_1.amount_paid_cents, _1.currency) }
      column("Balance", number: true) { money.(_1.total_cents.to_i - _1.amount_paid_cents.to_i, _1.currency) }
      column("Issued", &:issued_on)
      column("Due", &:due_on)
      column("Sent", &:sent_at)
      column("Paid in full", &:paid_at)
      column("Voided", &:voided_at)
      column("Property ID") { _1.property&.uid }
      column("Taxes") { taxes_of.(_1) }
      column("Prices include tax", &:prices_include_tax)
      column("Payment terms", &:payment_terms)
      column("Void reason", &:void_reason)
      column("Internal notes", &:internal_notes)
    end,
    Table.new("invoice_lines", "Invoice line items", "Each line on each invoice.", scope: -> { InvoiceLineItem.includes(:invoice) }, cursor: %i[invoice_id position id], &lines.("invoice", "Invoice number")),
    Table.new("payments", "Payments", "Each payment recorded against an invoice, by date received.", scope: -> { Payment.includes(:invoice, :recorded_by) }, cursor: %i[received_on id]) do
      column("Payment ID", &:uid)
      column("Invoice number") { _1.invoice.number }
      column("Received", &:received_on)
      column("Amount", number: true) { money.(_1.amount_cents, _1.currency) }
      column("Currency", &:currency)
      column("Method", &:payment_method)
      column("Source", &:source)
      column("Reference", &:reference)
      column("Note", &:note)
      column("Recorded by") { name_of.(_1.recorded_by) }
    end,
    Table.new("client_notes", "Client notes", "Notes your team wrote on clients' timelines.", scope: -> { ClientNote.includes(:client, :user) }, &notes.("Client ID") { _1.client.uid }),
    Table.new("request_notes", "Request notes", "Notes your team wrote on requests.", scope: -> { ServiceRequestNote.includes(:service_request, :user) }, &notes.("Request ID") { _1.service_request.uid }),
    Table.new("visit_notes", "Visit notes", "Notes your team wrote on visits.", scope: -> { VisitNote.includes(:visit, :user) }, &notes.("Visit ID") { _1.visit.uid })
  ].index_by(&:key).freeze

  def self.table(key) = TABLES.fetch(key.to_s)

  # Logs a CSV download; returns [csv, filename].
  def self.download!(key, by:)
    csv, count = table(key).generate
    create!(kind: key.to_s, requested_by: by, requested_by_email: by.email, rows_count: count)
    [ csv, "#{Current.business.handle.presence || "shadetree"}-#{key}-#{Current.business.today.iso8601}.csv" ]
  end

  def label = kind == "full" ? "Everything (zip)" : self.class.table(kind).label
end
