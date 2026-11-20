# An optional guard for a non-production environment (PLT-09, ADR 0025): off unless
# MAIL_SANDBOX=true, and refused on production by the deploy. With it on, only allow-listed
# recipients (exact addresses or "@domain") get a message. When anyone was blocked, the sandbox
# inbox (MAIL_SANDBOX_TO) also gets it, with the blocked To/Cc addresses in the subject; blocked
# Bcc addresses are never shown.
class MailSandbox
  def self.enabled? = ActiveModel::Type::Boolean.new.cast(ENV["MAIL_SANDBOX"])

  def self.allowlist = ENV.fetch("MAIL_ALLOWLIST", "").split(",").map { _1.strip.downcase }.reject(&:empty?)

  def self.allowed?(address)
    address = address.to_s.downcase
    allowlist.any? { |entry| entry.start_with?("@") ? address.end_with?(entry) : address == entry }
  end

  def self.delivering_email(message)
    blocked = { to: [], cc: [], bcc: [] }
    %i[to cc bcc].each do |field|
      addresses = Array(message.public_send(field))
      blocked[field] = addresses.reject { allowed?(_1) }
      message.public_send("#{field}=", (addresses - blocked[field]).presence)
    end
    return if blocked.values.all?(&:empty?)

    sandbox = ENV["MAIL_SANDBOX_TO"].presence
    message.to = [ *message.to, sandbox ].compact.uniq.presence if sandbox
    shown = blocked[:to] + blocked[:cc]
    message.subject = "[sandbox#{" → #{shown.join(", ")}" if shown.any?}] #{message.subject}"
    message.perform_deliveries = [ message.to, message.cc, message.bcc ].any?(&:present?)
  end
end
