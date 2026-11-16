# Delivers client-facing email over SMTP (NTF-01, ADR 0017). Temporary failures (4xx replies,
# timeouts, connection errors) are retried with backoff and marked "failed" after the last
# attempt. A permanent (5xx) reply fails at once; when the server refused the recipient
# itself, the address is suppressed for the business and flagged on the client. Bounces that
# happen after the server accepted a message are handled in the provider's dashboard.
class ClientMailDeliveryJob < ActionMailer::MailDeliveryJob
  ATTEMPTS = 5
  # Replies that mean "this mailbox doesn't exist or can't receive": 550/551/553, or any
  # 5.1.x enhanced status (bad destination address).
  RECIPIENT_REFUSED = /\A(55[013]\b|5\d\d[ -]5\.1\.\d)/
  self.log_arguments = false

  retry_on StandardError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    job.email_message&.mark!("failed", error: "The mail server couldn't be reached (#{error.class.name.demodulize}).", attempts: ATTEMPTS)
  end

  # Handlers are tried last-declared first, so the specific ones below win over the retry.
  # rescue_from (not discard_on) keeps the server's reply, which can name the address, out of
  # the logs and the error column.
  rescue_from Net::SMTPFatalError do |error|
    message = email_message or next
    code = error.message.to_s[/\A\d{3}(?:[ -]\d\.\d{1,3}\.\d{1,3})?/].to_s.tr("-", " ")
    if error.message.to_s.match?(RECIPIENT_REFUSED)
      Tenancy.with_business(message.business) do
        message.mark!("bounced", error: "The mail server refused this address (#{code}).")
        EmailSuppression.suppress!(message.to, reason: "hard_bounce", email_message: message)
      end
    else
      message.mark!("failed", error: "The mail server refused the message (#{code.presence || "permanent error"}).")
    end
  end
  # Bad SMTP credentials won't fix themselves on a retry.
  rescue_from Net::SMTPAuthenticationError do
    email_message&.mark!("failed", error: "The mail server rejected our credentials.")
  end
  # A deleted business or message has nothing left to send.
  rescue_from(ActiveRecord::RecordNotFound) { nil }

  def email_message
    id = arguments.last.is_a?(Hash) && arguments.last.dig(:params, :email_message_id)
    id && Tenancy.across_businesses(reason: "mail delivery bookkeeping") { EmailMessage.find_by(id:) }
  end
end
