# PAY-01: how invoices read for staff.
module InvoicesHelper
  STATUS_TONES = { "draft" => :neutral, "sent" => :info, "partially_paid" => :warning, "paid" => :success, "void" => :neutral }.freeze

  # The where-to for an invoice: the builder while it's a draft, else its page.
  def staff_invoice_path(invoice) = invoice.editable? ? edit_admin_invoice_path(invoice) : admin_invoice_path(invoice)

  # Its status, and Overdue beside it once the due date has passed (overdue isn't a status).
  def invoice_status_badge(invoice)
    safe_join([ badge(invoice.status_label, tone: STATUS_TONES.fetch(invoice.status)),
                (badge("Overdue", tone: :danger) if invoice.overdue?(current_business.today)) ].compact, " ")
  end

  EVENT_LABELS = { "created" => "Created", "sent" => "Sent", "revised" => "Revised", "partially_paid" => "Partly paid",
                   "paid" => "Paid", "voided" => "Voided", "reopened" => "Reopened" }.freeze

  # One line of its history: "Created from job J-0004 by Maria".
  def invoice_event_text(event)
    from = " from #{event.data["from"]} #{event.data["number"]}" if event.kind == "created" && event.data["from"]
    reason = ": “#{event.data["reason"]}”" if event.data["reason"].present?
    by = " by #{event.user.full_name}" if event.user
    "#{EVENT_LABELS.fetch(event.kind)}#{from}#{by}#{reason}"
  end
end
