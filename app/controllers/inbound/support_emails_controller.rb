# OPS-05: the Cloudflare Email Worker posts each email to the support address here, signed
# (InboundEmailIngress, docs/runbooks/inbound-email.md). There's no session or form, so no CSRF
# token: the signature is the only credential. Not configured (no secret) means not found.
module Inbound
  class SupportEmailsController < ActionController::API
    include ActionController::RateLimiting
    wrap_parameters false # the raw message is read here, capped; never parsed into params
    rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }, with: -> { reject(:too_many_requests, "rate_limited") }

    def create
      return head :not_found unless InboundEmailIngress.configured?
      return reject(413, "too_large") if request.content_length.to_i > InboundEmailIngress::MAX_BYTES

      request.body.rewind
      body = request.body.read(InboundEmailIngress::MAX_BYTES + 1).to_s
      return reject(413, "too_large") if body.bytesize > InboundEmailIngress::MAX_BYTES

      envelope = InboundEmailIngress.verify(timestamp: request.headers["X-Shadetree-Timestamp"], envelope: request.headers["X-Shadetree-Envelope"],
                                            signature: request.headers["X-Shadetree-Signature"], body:)
      return reject(:unauthorized, "bad_signature") if envelope.nil?
      return reject(:unprocessable_content, "not_support") unless InboundEmailIngress.support_recipient?(envelope.to)

      inbound = InboundEmailIngress.store!(body, envelope)
      Observability.log(:info, "inbound_email.accepted", inbound_email_id: inbound&.id, duplicate: inbound.nil?)
      head :no_content
    end

    private

    # Why, never who: no addresses, subjects or IPs in this line.
    def reject(status, reason)
      Observability.log(:warn, "inbound_email.rejected", reason:)
      head status
    end
  end
end
