# Development previews of client-facing email (NTF-01) at /rails/mailers. Each message type in
# EmailCatalog gets a preview here when its spec adds it.
class ClientMailerPreview < ActionMailer::Preview
  # The branded layout with the demo business (bin/rails db:seed).
  def test_message
    business = Business.order(:id).first
    ClientMailer.with(business_id: business.id, to: "dana@example.com", recipient_name: "Dana").test_message
  end
end

# QTE-04: the quote email, for the newest quote with lines (bin/rails db:seed makes one).
class QuoteMailerPreview < ActionMailer::Preview
  def sent
    quote = Tenancy.across_businesses(reason: "mailer preview") { Quote.joins(:line_items).order(:id).last }
    Tenancy.with_business(quote.business) do
      link = quote.client_link!
      QuoteMailer.with(business_id: quote.business_id, to: "maria@example.com", quote_id: quote.id, link_id: link.id,
                       subject: QuoteMailer.default_subject(quote), message: "Hi Maria,\n\nHere's the quote we talked about.").sent
    end
  end
end

# QTE-05: the client's approval confirmation and the team's notice, for the newest approved
# quote (bin/rails db:seed makes one).
class QuoteApprovalMailerPreview < ActionMailer::Preview
  def approved
    quote = approved_quote
    QuoteMailer.with(business_id: quote.business_id, to: "maria@example.com", quote_id: quote.id).approved
  end

  def team_notice
    quote = approved_quote
    response = Tenancy.with_business(quote.business) { quote.approval }
    QuoteActivityMailer.with(business_id: quote.business_id, response_id: response.id, user_id: quote.business.users.first.id).responded
  end

  private

  def approved_quote = Tenancy.across_businesses(reason: "mailer preview") { Quote.where(status: "approved").order(:id).last }
end

# CLI-03: the request acknowledgment and the team's notice, for the newest request
# (bin/rails db:seed makes one).
class RequestMailerPreview < ActionMailer::Preview
  def received
    request = latest_request
    RequestMailer.with(business_id: request.business_id, to: "hannah@example.com", request_id: request.id).received
  end

  def team_notice
    request = latest_request
    NewRequestMailer.with(business_id: request.business_id, request_id: request.id, user_id: request.business.owner_id).received
  end

  private

  def latest_request = Tenancy.across_businesses(reason: "mailer preview") { ServiceRequest.order(:id).last }
end

# JOB-05: a client's visit emails, for the seeded job with visits (bin/rails db:seed).
class VisitMailerPreview < ActionMailer::Preview
  def booked = update([ "scheduled", "scheduled" ])
  def moved = update([ "changed" ], before: "Mon, Nov 23, 2026 · Arrive 8–10 am")
  def cancelled = update([ "cancelled" ])
  def mixed = update([ "changed", "cancelled" ], before: "Mon, Nov 23, 2026 · 1 pm")

  # JOB-12: the seeded visit someone's on the way to.
  def on_the_way = on_the_way_email("visit_on_the_way")
  def on_the_way_update = on_the_way_email("visit_on_the_way_update")

  def reminder
    visit = Tenancy.across_businesses(reason: "mailer preview") { Visit.order(:id).first }
    VisitMailer.with(business_id: visit.business_id, to: "maria@example.com", job_id: visit.job_id, visit_id: visit.id).reminder
  end

  private

  # A booked visit put on the way for the preview only: the email is built inside a transaction
  # that's rolled back, so the demo data doesn't change.
  def on_the_way_email(kind)
    visit = Tenancy.across_businesses(reason: "mailer preview") { Visit.joins(:assignments).where(status: "scheduled").order(:id).first }
    arrives_at = OnTheWay.round_to_five(30.minutes.from_now)
    mail = VisitMailer.with(business_id: visit.business_id, to: "maria@example.com", job_id: visit.job_id, visit_id: visit.id, kind:, arrives_at: arrives_at.utc.iso8601).on_the_way
    ActiveRecord::Base.transaction do
      Tenancy.with_business(visit.business) { visit.update_columns(on_the_way_arrives_at: arrives_at, on_the_way_by_id: visit.assignments.first.user_id) }
      mail.message # built now, while the visit is on the way
      raise ActiveRecord::Rollback
    end
    mail
  end

  def update(kinds, before: nil)
    visits = Tenancy.across_businesses(reason: "mailer preview") { Visit.order(:id).limit(kinds.size).to_a }
    changes = visits.zip(kinds).map { |visit, kind| { "visit_id" => visit.id, "kind" => kind, "before" => (before if kind == "changed") } }
    VisitMailer.with(business_id: visits.first.business_id, to: "maria@example.com", job_id: visits.first.job_id, changes:).update
  end
end

# PAY-02: the invoice email, for the newest sent invoice (bin/rails db:seed makes one).
class InvoiceMailerPreview < ActionMailer::Preview
  def sent
    invoice = Tenancy.across_businesses(reason: "mailer preview") { Invoice.joins(:line_items).where(status: Invoice::OUTSTANDING).order(:id).last }
    return InvoiceMailer.with(business_id: Business.first.id, to: "maria@example.com").test_message unless invoice
    Tenancy.with_business(invoice.business) do
      link = invoice.client_link!
      InvoiceMailer.with(business_id: invoice.business_id, to: "maria@example.com", invoice_id: invoice.id, link_id: link.id,
                         subject: InvoiceMailer.default_subject(invoice), message: "Hi Maria,\n\nThanks again. Here's the invoice for the work.").sent
    end
  end
end

# PAY-05: a receipt for the newest recorded payment (bin/rails db:seed makes one).
class PaymentMailerPreview < ActionMailer::Preview
  def receipt
    payment = Tenancy.across_businesses(reason: "mailer preview") { Payment.order(:id).last }
    return PaymentMailer.with(business_id: Business.first.id, to: "maria@example.com").test_message unless payment
    PaymentMailer.with(business_id: payment.business_id, to: "maria@example.com", payment_id: payment.id).receipt
  end
end

# NTF-04: an automated message: the business's first template of its own, about its newest quote.
class AutomationMailerPreview < ActionMailer::Preview
  def template_email
    quote = Tenancy.across_businesses(reason: "mailer preview") { Quote.where.not(status: "draft").order(:id).last }
    Tenancy.with_business(quote.business) do
      template = MessageTemplate.custom.first || MessageTemplate.create!(name: "Quote follow-up", subject: "Any questions about {{document_number}}?",
                                                                        body: "Hi {{client_first_name}},\n\nJust checking in on the quote.")
      AutomationMailer.with(business_id: quote.business_id, to: "maria@example.com", template_id: template.id, subject_type: "Quote", subject_id: quote.id).template_email
    end
  end
end
