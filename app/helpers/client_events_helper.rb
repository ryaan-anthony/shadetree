# The words, icon and link for a line of the client timeline (CLI-05).
module ClientEventsHelper
  CHANNELS = { "email" => "by email", "link" => "as a link", "payment" => "(paid on the spot)" }.freeze

  # [icon, text, path]; the path is nil when there's nothing to open (or the subject is gone).
  def client_event_parts(event)
    subject = event.subject
    data = event.data
    case event.kind
    when "request_received"
      [ "inbox", "Request #{subject&.reference} received#{" (entered by staff)" if subject&.created_by_id}", subject && admin_service_request_path(subject) ]
    when "quote_sent"
      [ "send", "Quote #{subject&.number} sent #{CHANNELS[data["channel"]]} #{revision_note(data)}".squish, subject && staff_quote_path(subject) ]
    when "quote_viewed", "invoice_viewed"
      kind = event.kind.delete_suffix("_viewed")
      [ "eye", "#{event.client.display_name} opened #{kind} #{subject&.number}", subject && (kind == "quote" ? staff_quote_path(subject) : staff_invoice_path(subject)) ]
    when "quote_approved", "quote_declined", "quote_changes_requested"
      [ RESPONSE_ICONS.fetch(event.kind), quote_response_text(event, subject), subject && staff_quote_path(subject) ]
    when "visit_scheduled" then [ "calendar", "Visit booked for #{data["when"]}#{visit_note(subject, data)}", subject && admin_job_path(subject.job) ]
    when "follow_up_booked" # CLI-07: a site visit for a request (calls aren't on the timeline)
      [ "map-pin", "Site visit booked for #{data["when"]}#{" (#{subject.title.downcase_first})" if subject}", subject && admin_service_request_path(subject) ]
    when "visit_completed" then [ "check-square", "Visit done#{" for #{subject.job.number}" if subject}", subject && admin_job_path(subject.job) ]
    when "visit_reopened" then [ "rotate-ccw", "Visit reopened#{" for #{subject.job.number}" if subject}", subject && admin_job_path(subject.job) ]
    when "visit_cancelled" then [ "x-circle", "Visit on #{data["when"]} cancelled#{" (#{subject.job.number})" if subject}", subject && admin_job_path(subject.job) ]
    when "invoice_sent"
      [ "send", "Invoice #{subject&.number} sent #{CHANNELS[data["channel"]]} #{revision_note(data)}".squish, subject && staff_invoice_path(subject) ]
    when "invoice_paid" then [ "check-circle", "Invoice #{subject&.number} paid in full", subject && staff_invoice_path(subject) ]
    when "invoice_unpaid" then [ "rotate-ccw", "Invoice #{subject&.number} no longer paid in full", subject && staff_invoice_path(subject) ]
    when "payment_recorded"
      [ "dollar-sign", "Payment: #{payment_summary_text(data)}#{" on #{subject.invoice.number}" if subject}#{" (since deleted)" unless subject}", subject && admin_invoice_path(subject.invoice) ]
    when "payment_changed"
      [ "edit-3", "Payment changed: #{payment_summary_text(data["before"])} → #{payment_summary_text(data["after"])}", subject && admin_invoice_path(subject.invoice) ]
    when "payment_deleted" then [ "trash", "Payment deleted: #{payment_summary_text(data)} on #{subject&.number}", subject && admin_invoice_path(subject) ]
    when "email_bounced"
      # Bounces and (QA #274) other emails that couldn't be sent, linked to what they were about.
      # The line also carries an "Email not delivered" badge (the timeline partial).
      related = subject&.related
      about, path = case related
      when Quote then [ "Quote #{related.number}", staff_quote_path(related) ]
      when Invoice then [ "Invoice #{related.number}", staff_invoice_path(related) ]
      else [ ("“#{subject.subject}”" if subject&.subject), nil ]
      end
      [ "alert-triangle", subject ? "#{about || "An email"} to #{subject.to}: #{subject.problem_reason}" : "An email wasn't delivered", path ]
    when "note_added" then [ "message-square", subject&.body || "Note deleted", nil ]
    end
  end

  # Who did it: a client's own answer names them, staff's shows who recorded it.
  def client_event_actor(event)
    return event.client.display_name if event.data["via"] == "client"

    event.actor_label
  end

  RESPONSE_ICONS = { "quote_approved" => "check-circle", "quote_declined" => "x-circle", "quote_changes_requested" => "edit-3" }.freeze

  private

  def quote_response_text(event, quote)
    number = quote&.number
    if event.data["via"] == "client"
      { "quote_approved" => "#{event.client.display_name} approved quote #{number}", "quote_declined" => "#{event.client.display_name} declined quote #{number}",
        "quote_changes_requested" => "#{event.client.display_name} asked for changes to quote #{number}" }.fetch(event.kind)
    else
      { "quote_approved" => "Approval of quote #{number} recorded", "quote_declined" => "Quote #{number} marked declined",
        "quote_changes_requested" => "Changes to quote #{number} noted" }.fetch(event.kind)
    end
  end

  # A booked visit that has since moved or been cancelled says so.
  def visit_note(visit, data)
    return "" unless visit
    return " (#{visit.job.number}, since cancelled)" if visit.status == "cancelled"

    now = visit.when_label(with_year: true)
    now == data["when"] ? " (#{visit.job.number})" : " (#{visit.job.number}, now #{now})"
  end

  def revision_note(data) = data["revision"].to_i > 1 ? "(revision #{data["revision"]})" : ""
end
