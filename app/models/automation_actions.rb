# NTF-04: what an automation can do. Each action logs its result on the run ("done",
# "skipped" with why, or "failed" with the error), so one failing action doesn't hide the others.
module AutomationActions
  module_function

  # Each action in its own savepoint: a database error in one rolls back only that one, and the
  # run (and its log) carries on.
  def perform(action, run)
    type = action["type"]
    return run.note!(type.to_s, "failed", "Unknown action.") unless AutomationRule::ACTIONS.key?(type)

    result, detail = ActiveRecord::Base.transaction(requires_new: true) { public_send(type, action, run.subject, run) }
    run.note!(type, result, detail)
  rescue StandardError => e
    Rails.error.report(e, context: { automation_run_id: run.id, action: type })
    run.note!(type, "failed", e.message.truncate(200))
  end

  # The quote or invoice a record is about (a payment's invoice), for the once-per-document
  # rule, totals and the client's button.
  def document_for(subject)
    case subject
    when Payment then subject.invoice
    else subject
    end
  end

  # Client erasure (INS-02) leaves documents in place; automations never act for an erased client.
  def client_erased?(subject)
    client = client_for(subject)
    client.respond_to?(:erased?) && client.erased?
  end

  # A short name for the record in logs and notices: its number, never the client's name (so
  # nothing here needs scrubbing when a client is erased).
  def label_for(subject)
    subject.try(:number) || subject.try(:job)&.number || subject.model_name.human.downcase
  end

  def client_for(subject)
    case subject
    when Visit then subject.job.client
    when Payment then subject.invoice.client
    else subject.client
    end
  end

  def send_template(action, subject, run)
    template = MessageTemplate.custom.find_by(uid: action["template"]) or return [ "skipped", "The template was deleted." ]
    client = client_for(subject)
    email = client&.primary_email&.value or return [ "skipped", "The client has no email address." ]
    document = document_for(subject)
    delivery = AutomationDelivery.create_or_find_by!(message_template: template, subject: document)
    return [ "skipped", "The client already got “#{template.name}” about #{label_for(document)}." ] unless delivery.previously_new_record?

    AutomationMailer.send_later(:template_email, business: run.business, to: email, kind: "automated_message", related: document,
                                          template_id: template.id, subject_type: subject.class.name, subject_id: subject.id)
    [ "done", "Emailed “#{template.name}” to the client." ]
  end

  def notify_team(action, subject, run)
    permission = action["team"] == "schedule" ? :schedule : :office
    users = run.business.business_users.active.includes(:user).select { _1.can?(permission) }.map(&:user)
    return [ "skipped", "Nobody to notify." ] if users.empty?

    NotificationType.deliver("automation", business: run.business, to: users, title: "#{run.rule_name}: #{label_for(subject)}",
                             path: notice_path(subject))
    [ "done", "Notified #{users.size} #{"person".pluralize(users.size)}." ]
  end

  def create_job(_action, quote, _run)
    return [ "skipped", "The quote isn't approved." ] unless quote.status == "approved"
    return [ "skipped", "#{quote.job.number} already exists." ] if quote.job

    job = Job.from_quote!(quote)
    [ "done", "Created #{job.number}." ]
  end

  def invoice_job(_action, job, run)
    return [ "skipped", "The job isn't completed." ] unless job.status == "completed"
    return [ "skipped", "The job already has an invoice." ] if job.invoices.exists?

    invoice = Invoice.from_job!(job)
    email = job.client.primary_email&.value
    return [ "done", "Created #{invoice.number} as a draft: the client has no email address." ] unless email && invoice.sendable?

    Invoice.transaction do
      invoice_send = invoice.mark_sent!(by: nil, channel: "email", recipient: email)
      link = invoice.client_link!
      message = InvoiceMailer.send_later(:sent, business: run.business, to: email, kind: "invoice_sent", related: invoice, invoice_id: invoice.id,
                                                revision: invoice.revision, link_id: link.id, subject: InvoiceMailer.default_subject(invoice), message: nil)
      invoice_send.update!(email_message: message)
    end
    [ "done", "Created and emailed #{invoice.number}." ]
  end

  def tag_client(action, subject, _run)
    client = client_for(subject) or return [ "skipped", "No client." ]
    tag = action["tag"].to_s.squish.downcase
    return [ "skipped", "Already tagged “#{tag}”." ] if client.tags.include?(tag)

    client.update!(tags: client.tags + [ tag ])
    [ "done", "Tagged the client “#{tag}”." ]
  end

  def notice_path(subject)
    helpers = Rails.application.routes.url_helpers
    case subject
    when Quote then helpers.admin_quote_path(subject)
    when Invoice then helpers.admin_invoice_path(subject)
    when Payment then helpers.admin_invoice_path(subject.invoice)
    when Job then helpers.admin_job_path(subject)
    when Visit then helpers.admin_job_path(subject.job)
    when ServiceRequest then helpers.admin_service_request_path(subject)
    end
  end
end
