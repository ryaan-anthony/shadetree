# The words, icon and link for a line of the client timeline (CLI-05).
module ClientEventsHelper
  CHANNELS = { "email" => "by email", "link" => "as a link", "payment" => "with a payment" }.freeze

  # [icon, text, path]; the path is nil when the subject is gone.
  def client_event_parts(event)
    subject = event.subject
    data = event.data
    case event.kind
    when "request_received"
      [ "inbox", "Request #{subject&.reference} received#{" (entered by staff)" if data["source"] && data["source"] != "form"}", subject && admin_service_request_path(subject) ]
    when "quote_sent"
      [ "send", "Quote #{subject&.number} sent #{CHANNELS[data["channel"]]}#{revision_note(data)}".squish, subject && staff_quote_path(subject) ]
    when "quote_viewed", "invoice_viewed"
      kind = event.kind.delete_suffix("_viewed")
      [ "eye", "Opened #{kind} #{subject&.number}", subject && (kind == "quote" ? staff_quote_path(subject) : staff_invoice_path(subject)) ]
    when "quote_approved" then [ "check-circle", "Quote #{subject&.number} approved", subject && staff_quote_path(subject) ]
    when "quote_declined" then [ "x-circle", "Quote #{subject&.number} declined", subject && staff_quote_path(subject) ]
    when "quote_changes_requested" then [ "edit-3", "Changes asked for on quote #{subject&.number}", subject && staff_quote_path(subject) ]
    when "visit_scheduled" then [ "calendar", "Visit booked for #{data["when"]}#{" (#{subject.job.number})" if subject}", subject && admin_job_path(subject.job) ]
    when "visit_completed" then [ "check-square", "Visit done#{" for #{subject.job.number}" if subject}", subject && admin_job_path(subject.job) ]
    when "invoice_sent"
      [ "send", "Invoice #{subject&.number} sent #{CHANNELS[data["channel"]]}#{revision_note(data)}".squish, subject && staff_invoice_path(subject) ]
    when "invoice_paid" then [ "check-circle", "Invoice #{subject&.number} paid in full", subject && staff_invoice_path(subject) ]
    when "payment_recorded"
      [ "dollar-sign", "Payment: #{payment_summary_text(data)}#{" on #{subject.invoice.number}" if subject}", subject && admin_invoice_path(subject.invoice) ]
    when "email_bounced" then [ "alert-triangle", "Email to #{data["to"]} refused by the mail server", nil ]
    when "note_added" then [ "message-square", subject&.body || "Note deleted", nil ]
    end
  end

  private

  def revision_note(data) = data["revision"].to_i > 1 ? "(revision #{data["revision"]})" : ""
end
