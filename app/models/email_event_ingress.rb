# NTF-05 (ADR 0028): late bounces and complaints reach the app at POST /inbound/email_events,
# from whatever relays the client email (or a forwarder in front of it), signed with
# EMAIL_EVENTS_SECRET (docs/runbooks/email-events.md):
#
#   X-Shadetree-Timestamp: <unix seconds>
#   X-Shadetree-Signature: v1=hex(HMAC-SHA256(secret, "<timestamp>.<raw body>"))
#
# Requests more than 5 minutes off, with a bad signature, or over 256 KB are refused. The body is
# either our own JSON event (Content-Type application/json, see #parse_json) or a standard
# delivery status notification: a multipart/report message (RFC 3464) with the returned
# headers of our email. Both become Events; nothing in this module stores or logs them.
module EmailEventIngress
  MAX_BYTES = 256.kilobytes
  MAX_SKEW = 5.minutes
  SECRET_MIN_LENGTH = 32
  VERSION = 1
  TYPES = %w[bounce complaint delay].freeze
  JSON_KEYS = %w[version id type message_id reference recipient status reply_code occurred_at].freeze
  MAX_RECIPIENTS = 50
  # A DSN is one multipart/report, and the email it returns may hold two or three more. Deeper
  # nesting isn't a report: it's refused before it's parsed (each level costs a stack frame).
  MAX_MULTIPARTS = 6
  STATUS = /\A[245]\.\d{1,3}\.\d{1,3}\z/
  REPLY_CODE = /\A[245]\d\d\z/

  # type: bounce, complaint, delay, or other (a DSN's "delivered", "relayed", "expanded").
  # id: the sender's event id, or nil; key is what makes it stored once.
  Event = Data.define(:key, :type, :message_id, :reference, :recipient, :status, :reply_code, :occurred_at) do
    # Delays and temporary (4.x.x) statuses: the relay is still trying.
    def temporary? = type == "delay" || status.to_s.start_with?("4")
    def actionable? = type == "complaint" || (type == "bounce" && status.to_s.start_with?("5"))
  end

  module_function

  # EMAIL_EVENTS_SECRET (or credentials email_events_secret); without one the endpoint is off.
  def secret
    value = ENV["EMAIL_EVENTS_SECRET"].presence || Rails.application.credentials.email_events_secret.presence
    value if value.to_s.length >= SECRET_MIN_LENGTH
  end

  def configured? = secret.present?

  def signature(timestamp, body, key: secret) = "v1=#{OpenSSL::HMAC.hexdigest("SHA256", key, "#{timestamp}.#{body.b}")}"

  def verify(timestamp:, signature:, body:, now: Time.current)
    key = secret
    return false if key.nil? || !timestamp.to_s.match?(/\A\d{1,12}\z/) || (now.to_i - timestamp.to_i).abs > MAX_SKEW

    ActiveSupport::SecurityUtils.secure_compare(signature.to_s, signature(timestamp, body, key:))
  end

  # The events in a verified body, or nil when it isn't one of the two formats.
  def parse(body, content_type:)
    content_type.to_s.downcase.start_with?("application/json") ? parse_json(body) : parse_report(body)
  end

  # {"version": 1, "id": "…", "type": "bounce" | "complaint" | "delay", "message_id": "<…>",
  #  "reference": "<X-Shadetree-Email>", "recipient": "…", "status": "5.1.1", "reply_code": "550",
  #  "occurred_at": "<ISO 8601>"}. Strict: unknown keys, wrong types or values refuse the whole post.
  # A bounce or delay needs a status; every event needs message_id or reference.
  def parse_json(body)
    data = JSON.parse(body)
    return unless data.is_a?(Hash) && (data.keys - JSON_KEYS).empty? && data["version"] == VERSION
    return unless data.except("version").values.all? { _1.nil? || (_1.is_a?(String) && _1.length <= 998) }
    return unless TYPES.include?(data["type"]) && (data["message_id"].present? || data["reference"].present?)
    return if data["type"] != "complaint" && !data["status"].to_s.match?(STATUS)
    return if data["status"].present? && !data["status"].match?(STATUS)
    return if data["reply_code"].present? && !data["reply_code"].match?(REPLY_CODE)

    occurred_at = Time.iso8601(data["occurred_at"].to_s)
    key = data["id"].present? ? "id:#{data["id"]}" : "sha256:#{OpenSSL::Digest::SHA256.hexdigest(body)}"
    [ Event.new(key:, type: data["type"], message_id: message_id(data["message_id"]), reference: data["reference"].presence,
                recipient: address(data["recipient"]), status: data["status"].presence, reply_code: data["reply_code"].presence, occurred_at:) ]
  rescue JSON::ParserError, ArgumentError
    nil
  end

  # A multipart/report with a message/delivery-status part (per-message fields, then one block per
  # recipient) and our email's headers (text/rfc822-headers or message/rfc822). Each recipient is
  # an event, keyed by the body's digest and its place in the report. Anything the parser can't
  # take (an unknown transfer encoding, deep nesting) isn't a report: nil, so a 422.
  def parse_report(body)
    return if body.scan(/^content-type:[ \t]*multipart\//i).size > MAX_MULTIPARTS

    mail = Mail.new(body)
    parts = mail.all_parts
    report = parts.find { _1.mime_type == "message/delivery-status" } or return
    original = parts.find { _1.mime_type.in?(%w[text/rfc822-headers message/rfc822]) } or return
    headers = Mail.new(original.body.decoded.to_s.split(/\r?\n\r?\n/, 2).first.to_s)
    reference = headers["X-Shadetree-Email"]&.value.presence
    id = message_id(headers.message_id)
    return if id.nil? && reference.nil?

    per_message, *recipients = field_blocks(report.body.decoded.to_s)
    return if recipients.empty? || recipients.size > MAX_RECIPIENTS

    digest = OpenSSL::Digest::SHA256.hexdigest(body)
    recipients.each_with_index.map do |fields, index|
      status = fields["status"].to_s[/\A\s*([245]\.\d{1,3}\.\d{1,3})/, 1]
      at = fields["last-attempt-date"] || per_message["arrival-date"]
      Event.new(key: "sha256:#{digest}:#{index}", type: { "failed" => "bounce", "delayed" => "delay" }.fetch(fields["action"].to_s.strip.downcase, "other"),
                message_id: id, reference:, recipient: address(fields["original-recipient"] || fields["final-recipient"]), status:,
                reply_code: fields["diagnostic-code"].to_s[/\A\s*smtp\s*;\s*([245]\d\d)\b/i, 1], occurred_at: report_time(at))
    end
  rescue StandardError, SystemStackError
    nil
  end

  # Header-style blocks separated by blank lines, unfolded, names lowercased.
  def field_blocks(text)
    text.strip.split(/\r?\n[ \t]*\r?\n/).map do |block|
      block.split(/\r?\n(?![ \t])/).each_with_object({}) do |line, fields|
        name, value = line.split(":", 2)
        fields[name.strip.downcase] ||= value.to_s.gsub(/\s+/, " ").strip if value
      end
    end
  end

  def report_time(value)
    value && Time.rfc2822(value)
  rescue ArgumentError
    nil
  end

  def message_id(value) = value.to_s.strip.delete("<>").presence&.first(998)

  # "rfc822; Maria@Example.com" or a bare address, lowercased.
  def address(value) = value.to_s.sub(/\A\s*rfc822\s*;/i, "").strip.delete("<>").downcase.presence&.first(320)
end
