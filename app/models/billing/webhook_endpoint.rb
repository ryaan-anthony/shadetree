# POST /webhooks/stripe (BIL-04, ADR 0021): Stripe's events about our subscriptions. A plain Rack
# endpoint rather than a controller, so Rails never parses the body into params or logs it
# (PLT-10). Checks Stripe's signature with STRIPE_WEBHOOK_SECRET, stores the event's id and
# queues it (StripeEvent.receive!), and answers 200 at once; a bad signature gets 400.
class Billing::WebhookEndpoint
  MAX_BYTES = 1.megabyte
  JSON_HEADERS = { "content-type" => "application/json" }.freeze

  def self.call(env)
    request = ActionDispatch::Request.new(env)
    secret = ENV["STRIPE_WEBHOOK_SECRET"].presence
    return respond(503, "not configured") unless secret
    return respond(413, "too large") if request.content_length.to_i > MAX_BYTES

    payload = request.body.read(MAX_BYTES + 1).to_s
    return respond(413, "too large") if payload.bytesize > MAX_BYTES

    event = Stripe::Webhook.construct_event(payload, request.get_header("HTTP_STRIPE_SIGNATURE").to_s, secret)
    StripeEvent.receive!(event)
    respond(200, nil)
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    respond(400, "invalid")
  end

  def self.respond(status, error) = [ status, JSON_HEADERS.dup, [ (error ? { error: } : { received: true }).to_json ] ]
end
