# NTF-05 (ADR 0028): late bounce and complaint reports, signed (EmailEventIngress,
# docs/runbooks/email-events.md). There's no session or form, so no CSRF token: the signature is
# the only credential. Not configured (no secret) means not found.
#
# Matching happens here (EmailEvent.receive), so only events about one of our emails, to its own
# recipient, are stored. As on the support ingress, only failed verifications are rate limited,
# per IP. Log lines say what happened, never who: no addresses, Message-IDs or IPs.
module Inbound
  class EmailEventsController < ActionController::API
    FAILURES_PER_MINUTE = 30

    wrap_parameters false # the body is read here, capped; never parsed into params

    # Before the request is logged: an empty params hash instead of the parsed JSON event.
    def process_action(...)
      request.set_header("action_dispatch.request.request_parameters", {})
      super
    end

    def create
      return head :not_found unless EmailEventIngress.configured?
      return reject(:too_many_requests, "rate_limited", count: false) if failures >= FAILURES_PER_MINUTE
      return reject(413, "too_large") if request.content_length.to_i > EmailEventIngress::MAX_BYTES

      request.body.rewind
      body = request.body.read(EmailEventIngress::MAX_BYTES + 1).to_s
      return reject(413, "too_large") if body.bytesize > EmailEventIngress::MAX_BYTES
      return reject(:unauthorized, "bad_signature") unless EmailEventIngress.verify(timestamp: request.headers["X-Shadetree-Timestamp"],
                                                                                   signature: request.headers["X-Shadetree-Signature"], body:)

      events = EmailEventIngress.parse(body, content_type: request.content_type)
      return reject(:unprocessable_content, "unreadable", count: false) if events.nil?

      outcomes = events.map { EmailEvent.receive(_1) }
      Observability.log(:info, "email_events.received", outcomes: outcomes.tally.transform_keys(&:to_s))
      head :no_content
    end

    private

    def failures_key = "email-events:failures:#{request.remote_ip}"

    def failures = Rails.cache.read(failures_key).to_i

    def reject(status, reason, count: true)
      Rails.cache.increment(failures_key, 1, expires_in: 1.minute) if count
      Observability.log(:warn, "email_events.rejected", reason:)
      head status
    end
  end
end
