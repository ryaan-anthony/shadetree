# Stripe's notifications about connected accounts (PAY-03, PAY-04): account status, payments,
# refunds and disputes, signed with STRIPE_CONNECT_WEBHOOK_SECRET. A verified event is stored
# once (ConnectEvent) and processed in the background, so Stripe gets its 200 quickly and a
# repeated delivery does nothing. The body is read raw and never parsed into params, so none of
# it reaches the request log (PLT-10).
class Webhooks::StripeConnectController < ActionController::API
  MAX_BYTES = 512.kilobytes

  # Before the request is logged: an empty params hash instead of the parsed event.
  def process_action(...)
    request.set_header("action_dispatch.request.request_parameters", {})
    super
  end

  def create
    secret = ENV["STRIPE_CONNECT_WEBHOOK_SECRET"]
    return head(:service_unavailable) if secret.blank?

    payload = request.body.read(MAX_BYTES).to_s
    Stripe::Webhook::Signature.verify_header(payload, request.headers["Stripe-Signature"].to_s, secret)
    event = JSON.parse(payload)
    return head(:bad_request) unless event.is_a?(Hash) && event["id"].present? && event["object"] == "event"

    row = ConnectEvent.receive!(event)
    ProcessConnectEventJob.perform_later(row.id) if row
    head :ok
  rescue Stripe::SignatureVerificationError, JSON::ParserError
    head :bad_request
  end
end
