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

  EVENT_LABELS = { "created" => "Created", "sent" => "Sent", "revised" => "Revised", "revision_discarded" => "Changes discarded", "partially_paid" => "Partly paid",
                   "paid" => "Paid", "voided" => "Voided", "reopened" => "Awaiting payment again",
                   "payment_recorded" => "Payment recorded", "payment_changed" => "Payment changed", "payment_deleted" => "Payment deleted", "repriced" => "Re-priced" }.freeze

  # "$50.00, check (1042), received Nov 18, 2026", from Payment#summary.
  def payment_summary_text(summary)
    method = Payment::METHODS.fetch(summary["method"], summary["method"]).downcase
    method = "#{method} (#{summary["reference"]})" if summary["reference"]
    "#{money(Money.new(summary["amount_cents"].to_i, summary["currency"]))}, #{method}, received #{l(Date.iso8601(summary["received_on"]))}"
  end

  # One line of its history: "Created from job J-0004 by Maria".
  def invoice_event_text(event)
    from = " from #{event.data["from"]} #{event.data["number"]}" if event.kind == "created" && event.data["from"]
    reason = ": “#{event.data["reason"]}”" if event.data["reason"].present?
    by = " by #{event.user.full_name}" if event.user
    how = { "email" => " by email", "link" => " as a link", "payment" => " (paid on the spot)" }[event.data["channel"]] if event.kind == "sent"
    how = ": #{payment_summary_text(event.data["after"] || event.data)}" if event.kind.start_with?("payment_")
    how = ": #{payment_summary_text(event.data["before"])} → #{payment_summary_text(event.data["after"])}" if event.kind == "payment_changed"
    revision = " (revision #{event.data["revision"]})" if event.kind == "sent" && event.data["revision"].to_i > 1
    how = " for #{event.data["location"]} (#{Array(event.data["changed"]).join(" and ")})" if event.kind == "repriced"
    label = event.kind == "sent" && event.data["channel"] == "payment" ? "Marked sent" : EVENT_LABELS.fetch(event.kind)
    "#{label}#{how}#{revision}#{from}#{by}#{reason}"
  end
end
