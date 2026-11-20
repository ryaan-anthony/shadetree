require "test_helper"

# BIL-04: the Stripe webhook endpoint: signatures, duplicates, and the payload never logged.
class Billing::StripeWebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { ENV["STRIPE_WEBHOOK_SECRET"] = WEBHOOK_SECRET }
  teardown { ENV.delete("STRIPE_WEBHOOK_SECRET") }

  def deliver(payload, signature: stripe_signature(payload))
    post "/webhooks/stripe", params: payload, headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => signature }
  end

  test "a signed event is stored by id and queued; the same event again is accepted and ignored" do
    payload = stripe_event_json("customer.subscription.updated", { id: "sub_1", object: "subscription", customer: "cus_1" }, id: "evt_1")

    assert_enqueued_jobs 1, only: StripeEventJob do
      deliver(payload)
      deliver(payload)
    end

    assert_response :ok
    event = StripeEvent.sole
    assert_equal [ "evt_1", "customer.subscription.updated", "sub_1", "cus_1" ], event.values_at(:stripe_event_id, :event_type, :stripe_object_id, :customer_id)
  end

  test "a bad or missing signature, or a body that isn't JSON, is refused" do
    payload = stripe_event_json("invoice.paid", { id: "in_1", object: "invoice", customer: "cus_1" })

    deliver(payload, signature: stripe_signature(payload, secret: "whsec_other"))
    assert_response :bad_request
    deliver(payload, signature: "")
    assert_response :bad_request
    deliver("not json", signature: stripe_signature("not json"))
    assert_response :bad_request
    deliver(payload, signature: stripe_signature(payload, at: 10.minutes.ago))
    assert_response :bad_request
    assert_equal 0, StripeEvent.count
  end

  test "events we don't use are accepted and not stored" do
    deliver(stripe_event_json("customer.created", { id: "cus_1", object: "customer" }))
    assert_response :ok
    assert_equal 0, StripeEvent.count
  end

  test "without a signing secret the endpoint says so, so Stripe retries later" do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
    deliver(stripe_event_json("invoice.paid", { id: "in_1", object: "invoice", customer: "cus_1" }))
    assert_response :service_unavailable
  end

  test "the payload isn't written to the log" do
    payload = stripe_event_json("invoice.paid", { id: "in_1", object: "invoice", customer: "cus_1", customer_email: "payer@example.com" })
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    deliver(payload)
    assert_response :ok
    assert_no_match "payer@example.com", log.string
    assert_no_match "customer_email", log.string
  ensure
    Rails.logger = original
  end
end
