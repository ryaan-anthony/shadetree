# OPS-05: building signed requests the way the Cloudflare Email Worker sends them.
module InboundEmailHelpers
  INBOUND_SECRET = "test-inbound-secret-0123456789abcdef".freeze
  CLOUDFLARE_PASS = "mx.cloudflare.net; dkim=pass header.d=example.com header.s=s1 header.b=abc; " \
                    "dmarc=pass header.from=example.com policy.dmarc=reject; spf=pass smtp.mailfrom=bounce@example.com".freeze

  def with_inbound_email(secret: INBOUND_SECRET, enabled: "true")
    saved = ENV.to_h.slice("INBOUND_EMAIL_SECRET", "INBOUND_EMAIL_ENABLED")
    ENV["INBOUND_EMAIL_SECRET"], ENV["INBOUND_EMAIL_ENABLED"] = secret, enabled
    yield
  ensure
    ENV.delete("INBOUND_EMAIL_SECRET")
    ENV.delete("INBOUND_EMAIL_ENABLED")
    saved.each { ENV[_1] = _2 }
  end

  def raw_email(from: "user1@example.com", to: "support@getshadetree.com", subject: "Help", body: "It spins forever.", **headers)
    Mail.new do
      from from
      to to
      subject subject
      body body
      message_id "<#{SecureRandom.hex(8)}@example.com>"
      headers.each { |name, value| self[name.to_s.tr("_", "-")] = value }
    end.to_s
  end

  def inbound_headers(body, from: "bounce@example.com", to: "support@getshadetree.com", auth: CLOUDFLARE_PASS, at: Time.current, secret: INBOUND_SECRET)
    envelope = Base64.urlsafe_encode64({ from:, to:, auth: }.to_json, padding: false)
    { "Content-Type" => "message/rfc822", "X-Shadetree-Timestamp" => at.to_i.to_s, "X-Shadetree-Envelope" => envelope,
      "X-Shadetree-Signature" => InboundEmailIngress.signature(at.to_i, envelope, body, key: secret) }
  end

  def capture_json_log
    io = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io, level: :info, formatter: Observability::JsonLogFormatter.new))
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end
end
