# Delivers client-facing email over SMTP (NTF-01, ADR 0017). The SMTP reply decides what
# happens (see #classify):
# - the server refused the recipient's mailbox (a 5.1.x/5.2.1 status): the email is marked
#   bounced and the address suppressed for the business, flagged on the client;
# - any other permanent (5xx) reply, or credentials the server rejects: the email fails at once;
# - a temporary reply (4xx), a timeout or a dropped connection: retried with backoff for about
#   four hours, then marked failed.
# Any other error is a bug: the email is marked failed and the error re-raised for reporting.
# Most relays accept any well-formed recipient and bounce later; those bounces stay in the
# provider's dashboard. The server's reply text, which can name the address, isn't stored or logged.
class ClientMailDeliveryJob < ActionMailer::MailDeliveryJob
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

  retry_on Temporary, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    job.email_message&.mark!("failed", error: "The mail server couldn't take the email (#{error.message}).", attempts: ATTEMPTS)
  end

  # Handlers are tried last-declared first, so the specific ones win.
  rescue_from Permanent do |error|
    email_message&.mark!("failed", error: "The mail server refused the email (#{error.message}).")
  end
  rescue_from RecipientRefused do |error|
    message = email_message or next
    Tenancy.with_business(message.business) do
      message.mark!("bounced", error: "The mail server refused this address (#{error.message}).")
      EmailSuppression.suppress!(message.to, reason: "hard_bounce", email_message: message)
    end
  end
  # A deleted business or message has nothing left to send.
  rescue_from(ActiveRecord::RecordNotFound) { nil }

  # Sorts SMTP and network errors into the three outcomes above. The new errors carry only the
  # reply code, so neither the retry log lines nor the record name the address.
  def perform(...)
    super
  rescue *NETWORK_ERRORS => error
    raise Temporary, error.class.name.demodulize
  rescue Net::SMTPError => error
    raise self.class.classify(error)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue => error
    email_message&.mark!("failed", error: "Something went wrong sending this email.")
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

  def email_message
    id = arguments.last.is_a?(Hash) && arguments.last.dig(:params, :email_message_id)
    id && Tenancy.across_businesses(reason: "mail delivery bookkeeping") { EmailMessage.find_by(id:) }
  end
end
