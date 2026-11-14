# Staging must never email real clients (PLT-09). With MAIL_SANDBOX=true every message is
# delivered only to allow-listed recipients (exact addresses or "@domain"), and anything else is
# redirected to MAIL_SANDBOX_TO with the original recipients noted in the subject.
class MailSandbox
  def self.enabled? = ActiveModel::Type::Boolean.new.cast(ENV["MAIL_SANDBOX"])

  def self.allowlist = ENV.fetch("MAIL_ALLOWLIST", "").split(",").map { _1.strip.downcase }.reject(&:empty?)

  def self.allowed?(address)
    address = address.to_s.downcase
    allowlist.any? { |entry| entry.start_with?("@") ? address.end_with?(entry) : address == entry }
  end

  def self.delivering_email(message)
    recipients = [ *message.to, *message.cc, *message.bcc ]
    blocked = recipients.reject { allowed?(_1) }
    return if blocked.empty?

    sandbox = ENV["MAIL_SANDBOX_TO"].presence
    message.to = (recipients - blocked).presence || Array(sandbox)
    message.cc = message.bcc = nil
    message.subject = "[sandbox → #{blocked.join(", ")}] #{message.subject}"
    message.perform_deliveries = message.to.present?
  end
end
