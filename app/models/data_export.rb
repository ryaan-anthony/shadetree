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

  TABLES = [
    Table.new("clients", "Clients", "One row per client, with their emails and phones.", scope: -> { Client.includes(:contact_methods).order(:id) }) do
      column("Client ID", &:uid)
      column("Name", &:display_name)
      column("Company", &:company_name)
      column("Emails") { |c| c.contact_methods.select(&:email?).map(&:value) }
      column("Phones") { |c| c.contact_methods.select(&:phone?).map(&:value) }
      column("Tags", &:tags)
      column("Tax exempt", &:tax_exempt)
      column("Notes", &:notes)
      column("Archived", &:archived_at)
      column("Created", &:created_at)
    end,
    Table.new("properties", "Properties", "Client addresses; one client can have several.", scope: -> { Property.includes(:client).order(:client_id, :position, :id) }) do
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
    Table.new("requests", "Requests", "Requests for work from your form or added by your team.", scope: -> { ServiceRequest.includes(:client).order(:id) }) do
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
    end,
    Table.new("quotes", "Quotes", "One row per quote, with its totals.", scope: -> { Quote.includes(:client, :created_by).order(:id) }) do
      column("Quote number", &:number)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Title", &:title)
      column("Status", &:status)
      column("Currency", &:currency)
      column("Subtotal") { money.(_1.subtotal_cents) }
      column("Discount") { money.(_1.discount_total_cents) }
      column("Tax") { money.(_1.tax_cents) }
      column("Total") { money.(_1.total_cents) }
      column("Expires", &:expires_on)
      column("Sent", &:sent_at)
      column("Created", &:created_at)
      column("Created by") { name_of.(_1.created_by) }
    end,
    Table.new("quote_lines", "Quote line items", "Each line on each quote.", scope: -> { QuoteLineItem.includes(:quote).order(:quote_id, :position, :id) }) do
      column("Quote number") { _1.quote.number }
      column("Position", &:position)
      column("Item", &:name)
      column("Description", &:description)
      column("Quantity") { _1.quantity&.to_s("F") }
      column("Unit", &:unit)
      column("Unit price") { money.(_1.unit_price_cents) }
      column("Taxable", &:taxable)
    end,
    Table.new("jobs", "Jobs", "One row per job, with its totals.", scope: -> { Job.includes(:client, :quote).order(:id) }) do
      column("Job number", &:number)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Title", &:title)
      column("Status", &:status)
      column("From quote") { _1.quote&.number }
      column("Currency", &:currency)
      column("Total") { money.(_1.total_cents) }
      column("Created", &:created_at)
      column("Completed", &:completed_at)
      column("Cancelled", &:cancelled_at)
      column("Cancel reason", &:cancel_reason)
    end,
    Table.new("visits", "Visits", "Each scheduled visit, with who was on it.", scope: -> { Visit.includes(:job, :assignees).order(:scheduled_on, :id) }) do
      column("Visit ID", &:uid)
      column("Job number") { _1.job.number }
      column("Date", &:scheduled_on)
      column("Timing", &:timing)
      column("Starts", &:starts_at)
      column("Duration (minutes)", &:duration_minutes)
      column("Status", &:status)
      column("Crew") { |v| v.assignees.map(&:full_name) }
      column("Instructions", &:instructions)
      column("Completed", &:completed_at)
    end,
    Table.new("invoices", "Invoices", "One row per invoice, with totals and what's been paid.", scope: -> { Invoice.includes(:client, :job).order(:id) }) do
      column("Invoice number", &:number)
      column("Client ID") { _1.client.uid }
      column("Client") { _1.client.display_name }
      column("Title", &:title)
      column("Status", &:status)
      column("From job") { _1.job&.number }
      column("Currency", &:currency)
      column("Subtotal") { money.(_1.subtotal_cents) }
      column("Discount") { money.(_1.discount_total_cents) }
      column("Tax") { money.(_1.tax_cents) }
      column("Total") { money.(_1.total_cents) }
      column("Paid") { money.(_1.amount_paid_cents) }
      column("Balance") { money.(_1.total_cents.to_i - _1.amount_paid_cents.to_i) }
      column("Issued", &:issued_on)
      column("Due", &:due_on)
      column("Sent", &:sent_at)
      column("Paid in full", &:paid_at)
      column("Voided", &:voided_at)
    end,
    Table.new("invoice_lines", "Invoice line items", "Each line on each invoice.", scope: -> { InvoiceLineItem.includes(:invoice).order(:invoice_id, :position, :id) }) do
      column("Invoice number") { _1.invoice.number }
      column("Position", &:position)
      column("Item", &:name)
      column("Description", &:description)
      column("Quantity") { _1.quantity&.to_s("F") }
      column("Unit", &:unit)
      column("Unit price") { money.(_1.unit_price_cents) }
      column("Taxable", &:taxable)
    end,
    Table.new("payments", "Payments", "Each payment recorded against an invoice.", scope: -> { Payment.includes(:invoice, :recorded_by).order(:received_on, :id) }) do
      column("Payment ID", &:uid)
      column("Invoice number") { _1.invoice.number }
      column("Received", &:received_on)
      column("Amount") { money.(_1.amount_cents) }
      column("Currency", &:currency)
      column("Method", &:payment_method)
      column("Source", &:source)
      column("Reference", &:reference)
      column("Note", &:note)
      column("Recorded by") { name_of.(_1.recorded_by) }
    end
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
