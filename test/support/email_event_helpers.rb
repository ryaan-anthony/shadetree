# NTF-05: signed bounce and complaint reports, as a relay or forwarder posts them.
module EmailEventHelpers
  EVENTS_SECRET = "test-email-events-secret-0123456789abcdef".freeze

  def with_email_events(secret: EVENTS_SECRET)
    saved = ENV["EMAIL_EVENTS_SECRET"]
    ENV["EMAIL_EVENTS_SECRET"] = secret
    yield
  ensure
    saved ? ENV["EMAIL_EVENTS_SECRET"] = saved : ENV.delete("EMAIL_EVENTS_SECRET")
  end

  def event_headers(body, at: Time.current, secret: EVENTS_SECRET, type: "application/json")
    { "Content-Type" => type, "X-Shadetree-Timestamp" => at.to_i.to_s,
      "X-Shadetree-Signature" => EmailEventIngress.signature(at.to_i, body, key: secret) }
  end

  def event_json(email, **fields)
    { version: 1, id: "evt-#{SecureRandom.hex(4)}", type: "bounce", message_id: "<#{email.provider_message_id}>", recipient: email.to,
      status: "5.1.1", reply_code: "550", occurred_at: Time.current.iso8601 }.merge(fields).compact.to_json
  end

  # A multipart/report DSN (RFC 3464) returning our email's headers, one block per recipient.
  def dsn_report(email, recipients: [ [ email.to, "failed", "5.1.1", "smtp; 550 5.1.1 <#{email.to}>: no such user" ] ], message_id: email.provider_message_id, reference: email.uid)
    blocks = recipients.map { |to, action, status, diagnostic| "Final-Recipient: rfc822; #{to}\r\nAction: #{action}\r\nStatus: #{status}\r\nDiagnostic-Code: #{diagnostic}\r\nLast-Attempt-Date: #{Time.current.rfc2822}" }
    headers = [ ("Message-ID: <#{message_id}>" if message_id), ("X-Shadetree-Email: #{reference}" if reference), "To: #{email.to}", "Subject: Your quote" ].compact.join("\r\n")
    <<~MAIL.gsub("\n", "\r\n").gsub("\r\r\n", "\r\n")
      From: Mail Delivery System <mailer-daemon@mx.example>
      To: no-reply@getshadetree.com
      Subject: Undelivered Mail Returned to Sender
      MIME-Version: 1.0
      Content-Type: multipart/report; report-type=delivery-status; boundary="b1"

      --b1
      Content-Type: text/plain

      Your message could not be delivered.
      --b1
      Content-Type: message/delivery-status

      Reporting-MTA: dns; mx.example

      #{blocks.join("\r\n\r\n")}
      --b1
      Content-Type: text/rfc822-headers

      #{headers}
      --b1--
    MAIL
  end

  # A client email that went out: its send records the CCs, as the send pages do.
  def sent_email(business, to: "maria@example.com", cc: nil, sent_at: 1.hour.ago, quote: nil, by: nil)
    as_business(business) do
      quote ||= sample_quote
      email = EmailMessage.create!(kind: "quote_sent", to:, related: quote)
      quote.reload.mark_sent!(by:, channel: "email", recipient: to, cc:, email_message: email)
      email.mark!("sent", at: sent_at, provider_message_id: "#{SecureRandom.uuid}@getshadetree.com")
      email
    end
  end

  def sample_quote
    quote = Quote.start(client: Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]))
    quote.title = "Cricket in the basement"
    quote.sync_line_items([ { "key" => "a", "name" => "Inspection", "quantity" => "1", "unit_price" => "60", "taxable" => "0" } ])
    quote.save!
    quote
  end
end
