# OPS-05: email to the support address reaches the app from a Cloudflare Email Worker
# (ADR 0021, docs/runbooks/inbound-email.md). The Worker posts the raw message to
# POST /inbound/support_email and signs it with INBOUND_EMAIL_SECRET:
#
#   X-Shadetree-Timestamp: <unix seconds>
#   X-Shadetree-Envelope:  base64url(JSON {"from":…, "to":…, "auth":<Cloudflare's first Authentication-Results>})
#   X-Shadetree-Signature: v1=hex(HMAC-SHA256(secret, "<timestamp>.<envelope header>.<raw body>"))
#
# Requests more than 5 minutes off, with a bad signature, or over 25 MiB are refused; accepted
# ones become an ActionMailbox::InboundEmail, routed to SupportMailbox.
module InboundEmailIngress
  MAX_BYTES = 25.megabytes # Cloudflare Email Routing's own limit (MiB)
  MAX_SKEW = 5.minutes
  SECRET_MIN_LENGTH = 32
  Envelope = Data.define(:from, :to, :auth)

  module_function

  # INBOUND_EMAIL_SECRET (or credentials inbound_email_secret); without one the ingress is off.
  def secret
    value = ENV["INBOUND_EMAIL_SECRET"].presence || Rails.application.credentials.inbound_email_secret.presence
    value if value.to_s.length >= SECRET_MIN_LENGTH
  end

  def configured? = secret.present?

  # Whether emails tell members they can answer by email (INBOUND_EMAIL_ENABLED, with a secret).
  def replies_by_email? = configured? && ActiveModel::Type::Boolean.new.cast(ENV["INBOUND_EMAIL_ENABLED"].presence) == true

  def signature(timestamp, envelope, body, key: secret)
    "v1=#{OpenSSL::HMAC.hexdigest("SHA256", key, "#{timestamp}.#{envelope}.#{body.b}")}"
  end

  # The Envelope the Worker signed, or nil when the request isn't genuine and fresh.
  def verify(timestamp:, envelope:, signature:, body:, now: Time.current)
    key = secret
    return if key.nil? || !timestamp.to_s.match?(/\A\d{1,12}\z/) || (now.to_i - timestamp.to_i).abs > MAX_SKEW
    return unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, signature(timestamp, envelope, body, key:))

    data = JSON.parse(Base64.urlsafe_decode64(envelope.to_s))
    Envelope.new(from: data["from"].to_s.first(320), to: data["to"].to_s.first(320), auth: data["auth"].to_s.first(4_000)) if data.is_a?(Hash)
  rescue ArgumentError, JSON::ParserError
    nil
  end

  # support@ and support+anything@ on the support address's domain.
  def support_recipient?(address)
    base_local, base_domain = ContactMailer.support_address.downcase.split("@", 2)
    local, domain = address.to_s.strip.downcase.delete_prefix("<").delete_suffix(">").split("@", 2)
    domain == base_domain && (local == base_local || local.to_s.start_with?("#{base_local}+"))
  end

  # Stores it once (a retry of the same message is a no-op) and routes it to SupportMailbox.
  def store!(source, envelope)
    return if ActionMailbox::InboundEmail.exists?(message_checksum: OpenSSL::Digest::SHA1.hexdigest(source))

    ActionMailbox::InboundEmail.create_and_extract_message_id!(source, envelope_from: envelope.from, envelope_to: envelope.to, auth_results: envelope.auth)
  end
end
