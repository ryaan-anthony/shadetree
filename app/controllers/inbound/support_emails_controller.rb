# OPS-05: the Cloudflare Email Worker posts each email to the support address here, signed
# (InboundEmailIngress, docs/runbooks/inbound-email.md). There's no session or form, so no CSRF
# token: the signature is the only credential. Not configured (no secret) means not found.
#
# Only failed verifications are rate limited, per IP: genuine posts come from Cloudflare's shared
# egress addresses (and the app may sit behind a tunnel), so counting them would throttle mail.
module Inbound
  class SupportEmailsController < ActionController::API
    FAILURES_PER_MINUTE = 30

    wrap_parameters false # the raw message is read here, capped; never parsed into params

    def create
      return head :not_found unless InboundEmailIngress.configured?
      return reject(:too_many_requests, "rate_limited", count: false) if failures >= FAILURES_PER_MINUTE
      return reject(413, "too_large") if request.content_length.to_i > InboundEmailIngress::MAX_BYTES

      request.body.rewind
      body = request.body.read(InboundEmailIngress::MAX_BYTES + 1).to_s
      return reject(413, "too_large") if body.bytesize > InboundEmailIngress::MAX_BYTES

      envelope = InboundEmailIngress.verify(timestamp: request.headers["X-Shadetree-Timestamp"], envelope: request.headers["X-Shadetree-Envelope"],
                                            signature: request.headers["X-Shadetree-Signature"], body:)
      return reject(:unauthorized, "bad_signature") if envelope.nil?
      return reject(:unprocessable_content, "not_support", count: false) unless InboundEmailIngress.support_recipient?(envelope.to)

      inbound = InboundEmailIngress.store!(body, envelope)
      Observability.log(:info, "inbound_email.accepted", inbound_email_id: inbound&.id, duplicate: inbound.nil?)
      head :no_content
    end

    private

    def failures_key = "inbound-email:failures:#{request.remote_ip}"

    def failures = Rails.cache.read(failures_key).to_i

    # Why, never who: no addresses, subjects or IPs in this line.
    def reject(status, reason, count: true)
      Rails.cache.increment(failures_key, 1, expires_in: 1.minute) if count
      Observability.log(:warn, "inbound_email.rejected", reason:)
      head status
    end
  end
end
