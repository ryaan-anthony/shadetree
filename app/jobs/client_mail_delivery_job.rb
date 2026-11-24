# Delivers client-facing email over SMTP (NTF-01, ADR 0017). The SMTP reply decides what
# happens (see #classify):
# - the server refused the recipient's mailbox (a 5.1.x/5.2.1 status): the email is marked
#   bounced and the address suppressed for the business, flagged on the client;
# - any other permanent (5xx) reply, or credentials the server rejects: the email fails at once;
# - a temporary reply (4xx), a timeout or a dropped connection: retried with backoff for about
#   four hours, then marked failed.
# Any other error is a bug: the email is marked failed and the error re-raised for reporting.
# Each of these puts the email on the client's timeline and tells the team (QA #274, NTF-02).
# Most relays accept any well-formed recipient and bounce later; those late reports arrive at
# /inbound/email_events and go through the same rules (EmailEvent, NTF-05, ADR 0028). The
# server's reply text, which can name the address, isn't stored or logged.
class ClientMailDeliveryJob < ActionMailer::MailDeliveryJob
  include ReportsUnhandledErrors # PLT-10
  ATTEMPTS = 10 # polynomial backoff: about four hours in all
  # Enhanced status codes that mean "this mailbox can't receive" (RFC 3463): bad mailbox, bad
  # system, bad address syntax, mailbox moved, no MX; mailbox disabled.
  RECIPIENT_STATUSES = %w[5.1.1 5.1.2 5.1.3 5.1.6 5.1.10 5.2.1].freeze
  NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET,
                     Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT, Errno::EPIPE, EOFError, IOError,
                     SocketError, OpenSSL::SSL::SSLError ].freeze

  class Temporary < StandardError; end
  class Permanent < StandardError; end
  class RecipientRefused < Permanent; end

  self.log_arguments = false
  # Sends are recorded in the same transaction as the email (QTE-04, PAY-02): the job waits
  # for the commit, so it never runs against a send or link that isn't there yet.
  self.enqueue_after_transaction_commit = true

  retry_on Temporary, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    job.email_message&.mark!("failed", error: "The mail server couldn't take the email (#{error.message}).", attempts: ATTEMPTS, announce: true)
  end

  # Handlers are tried last-declared first, so the specific ones win.
  rescue_from Permanent do |error|
    email_message&.mark!("failed", error: "The mail server refused the email (#{error.message}).", announce: true)
  end
  rescue_from RecipientRefused do |error|
    message = email_message or next
    Tenancy.with_business(message.business) do
      if cc?
        # With CCs the reply doesn't say which address was refused, so none is blamed.
        message.mark!("bounced", error: "The mail server refused one of the addresses (#{error.message}).")
      else
        message.mark!("bounced", error: "The mail server refused this address (#{error.message}).")
        EmailSuppression.suppress!(message.to, reason: "hard_bounce", email_message: message)
      end
    end
  end
  # A deleted business or message has nothing left to send.
  rescue_from(ActiveRecord::RecordNotFound) { nil }

  # Sorts SMTP and network errors into the three outcomes above. The new errors carry only the
  # reply code, so neither the retry log lines nor the record name the address.
  def perform(...)
    # OPS-04: email queued before a business was suspended isn't sent.
    return email_message.mark!("failed", error: "Not sent: the business is suspended.") if email_message&.business&.suspended?

    super
  rescue *NETWORK_ERRORS => error
    raise Temporary, error.class.name.demodulize
  rescue PdfRenderer::Error
    raise Temporary, "the PDF couldn't be made yet" # an attached PDF (QTE-04): busy or slow Chrome
  rescue Net::SMTPError => error
    raise self.class.classify(error)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue => error
    email_message&.mark!("failed", error: "Something went wrong sending this email.", announce: true)
    raise error
  end

  def self.classify(error)
    reply = error.message.to_s
    code = reply[/\A\d{3}/].to_s
    status = reply[/\A\d{3}[ -](\d\.\d{1,3}\.\d{1,3})/, 1]
    label = [ code, status ].compact_blank.join(" ").presence || "no reply code"
    return Temporary.new(label) if code.start_with?("4") || error.is_a?(Net::SMTPServerBusy)
    permanent_reply = error.is_a?(Net::SMTPFatalError) || error.is_a?(Net::SMTPSyntaxError)
    return RecipientRefused.new(label) if permanent_reply && RECIPIENT_STATUSES.include?(status)
    return Permanent.new("credentials rejected, #{label}") if error.is_a?(Net::SMTPAuthenticationError)

    Permanent.new(label)
  end

  def cc? = arguments.last.is_a?(Hash) && arguments.last.dig(:params, :cc).present?

  def email_message
    id = arguments.last.is_a?(Hash) && arguments.last.dig(:params, :email_message_id)
    id && Tenancy.across_businesses(reason: "mail delivery bookkeeping") { EmailMessage.find_by(id:) }
  end
end
