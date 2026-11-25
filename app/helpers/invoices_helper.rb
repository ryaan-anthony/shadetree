# PAY-01: how invoices read for staff.
module InvoicesHelper
  # The where-to for an invoice: the builder while it's a draft, else its page.
  def staff_invoice_path(invoice) = invoice.editable? ? edit_admin_invoice_path(invoice) : admin_invoice_path(invoice)

  # Its status (PLT-17's map), and Overdue beside it once the due date has passed (overdue isn't
  # a status). A sent invoice being revised says Revising, in its status's tone.
  def invoice_status_badge(invoice)
    safe_join([ status_badge(:invoice, invoice.status, invoice.status_label),
                (status_badge(:invoice, "overdue") if invoice.overdue?(current_business.today)) ].compact, " ")
  end

  EVENT_LABELS = { "created" => "Created", "sent" => "Sent", "revised" => "Revised", "revision_discarded" => "Changes discarded", "partially_paid" => "Partly paid",
                   "paid" => "Paid", "voided" => "Voided", "reopened" => "Awaiting payment again",
                   "payment_recorded" => "Payment recorded", "payment_changed" => "Payment changed", "payment_deleted" => "Payment deleted", "repriced" => "Re-priced",
                   "payment_received" => "Paid online", "payment_refunded" => "Refund in Stripe", "payment_disputed" => "Dispute in Stripe",
                   "progress_refitted" => "Fitted to what's left" }.freeze

  # "$50.00, check (1042), received Nov 18, 2026", from Payment#summary.
  def payment_summary_text(summary)
    method = Payment::METHODS.fetch(summary["method"], summary["method"]).downcase
    method = summary["detail"] if summary["detail"] # PAY-04: "Visa ending 4242"
    # A recorded payment's reference (a check number) is the business's own; an online one's is
    # Stripe's, shown only in the invoice's Payments card (PLT-18).
    method = "#{method} (#{summary["reference"]})" if summary["reference"] && summary["method"].in?(Payment::RECORDED_METHODS)
    "#{money(Money.new(summary["amount_cents"].to_i, summary["currency"]))}, #{method}, received #{l(Date.iso8601(summary["received_on"]))}"
  end

  # One line of its history: "Created from job J-0004 by Maria".
  def invoice_event_text(event)
    from = " from #{event.data["from"]} #{event.data["number"]}" if event.kind == "created" && event.data["from"]
    reason = ": “#{event.data["reason"]}”" if event.data["reason"].present?
    by = " by #{event.actor_label}" if event.user
    how = { "email" => " by email", "link" => " as a link", "payment" => " (paid on the spot)" }[event.data["channel"]] if event.kind == "sent"
    how = ": #{payment_summary_text(event.data["after"] || event.data)}" if event.kind.start_with?("payment_")
    how = ": #{payment_summary_text(event.data["before"])} → #{payment_summary_text(event.data["after"])}" if event.kind == "payment_changed"
    how = ": #{money(Money.new(event.data["refunded_cents"].to_i, event.data["currency"]))} of #{payment_summary_text(event.data)}" if event.kind == "payment_refunded"
    how = ": #{Payment::DISPUTE_STATUSES.fetch(event.data["dispute"].to_s, "updated").downcase}, #{payment_summary_text(event.data)}" if event.kind == "payment_disputed"
    revision = " (revision #{event.data["revision"]})" if event.kind == "sent" && event.data["revision"].to_i > 1
    how = " for #{event.data["location"]} (#{Array(event.data["changed"]).join(" and ")})" if event.kind == "repriced"
    how = refit_text(event.data) if event.kind == "progress_refitted"
    label = event.kind == "sent" && event.data["channel"] == "payment" ? "Marked sent" : EVENT_LABELS.fetch(event.kind)
    label = "Nothing due: marked paid" if event.kind == "paid" && event.data["nothing_due"] # PAY-08
    "#{label}#{how}#{revision}#{from}#{by}#{reason}"
  end

  # PAY-08 (B18): ": Roof lowered to what's left; Gutters taken off, nothing left to bill".
  def refit_text(data)
    parts = [ ("#{Array(data["lowered"]).to_sentence} lowered to what's left" if Array(data["lowered"]).any?),
              ("#{Array(data["removed"]).to_sentence} taken off, nothing left to bill" if Array(data["removed"]).any?) ].compact
    ": #{parts.join("; ")}"
  end
end
