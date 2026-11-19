# The base for every client-facing email (NTF-01, ADR 0017). Subclasses (QuoteMailer,
# InvoiceMailer, …) build messages with #client_mail and are sent with .send_later:
#
#   QuoteMailer.send_later(:sent, business:, to: "maria@example.com", kind: "quote_sent", related: quote, quote_id: quote.id)
#
# which records an EmailMessage (so the related record can show what happened), then
# delivers in the background with retries. Each message:
# - comes from the platform address as "<Business> via Shadetree", with the business's
#   email as reply-to, so replies reach the owner;
# - uses the branded layout (logo, color, contact footer) with a plain-text part;
# - isn't sent to an address the business has suppressed (the mail server refused it).
class ClientMailer < ApplicationMailer
  layout "mailer_client"
  helper FormattingHelper
  self.delivery_job = ClientMailDeliveryJob

  around_action :within_business
  after_deliver :record_sent

  def self.send_later(action, business:, to:, kind:, related: nil, **params)
    EmailCatalog.find(kind)
    message = Tenancy.with_business(business) { EmailMessage.create!(kind:, to:, related:) }
    with(**params, business_id: business.id, email_message_id: message.id).public_send(action).deliver_later
    message
  end

  # Sends the business owner a sample, so they can check their branding and reply-to.
  def test_message
    @recipient_name = params[:recipient_name]
    client_mail subject: "Test email from #{@business.name}"
  end

  private

  # NTF-03: the business's own subject for this email, filled in, with its opening text in
  # @intro for the views; nil (and the default wording) when it hasn't customized the message.
  def custom_subject(kind, values)
    template = MessageTemplate.for_kind(kind) or return
    @intro = MessageTemplate.render(template.body, values)
    MessageTemplate.render(template.subject, values)
  end

  def within_business(&)
    @business = Business.find(params[:business_id])
    @branding = @business.branding
    Tenancy.with_business(@business) do
      @email_message = EmailMessage.find_by(id: params[:email_message_id])
      yield
    end
  end

  # The document changed after the email was queued (revised, voided, answered): what would go
  # out isn't what staff sent, so it's marked failed for them to send again.
  def skip_changed_document(subject:, error:)
    @email_message&.mark!("failed", subject:, error:)
    mail(to: @email_message&.to || params[:to], subject:, body: "").tap { _1.perform_deliveries = false }
  end

  def client_mail(subject:, to: @email_message&.to || params[:to], **options)
    if EmailSuppression.suppressed?(to)
      @email_message&.mark!("suppressed", subject:)
      return mail(to:, subject:).tap { _1.perform_deliveries = false }
    end
    unless ActionMailer::Base.perform_deliveries # production without SMTP settings
      @email_message&.mark!("failed", subject:, error: "Email sending isn't set up yet.")
      return mail(to:, subject:)
    end

    headers["X-Shadetree-Email"] = @email_message&.uid
    mail(to:, subject:, from: email_address_with_name(self.class.sending_address, "#{@business.name} via Shadetree"),
         reply_to: @business.email.presence, **options)
  end

  def record_sent
    return unless @email_message && message.perform_deliveries

    # The Message-ID we set (ApplicationMailer), to match the message up in the provider's logs.
    provider_id = message.message_id.to_s.delete("<>").presence
    @email_message.mark!("sent", provider_message_id: provider_id, subject: message.subject, attempts: @email_message.attempts + 1, error: nil)
  end

  # The address part of MAIL_FROM (the platform sending domain, ADR 0017).
  def self.sending_address = Mail::Address.new(default[:from]).address
end
