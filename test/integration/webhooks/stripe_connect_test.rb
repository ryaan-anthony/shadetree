require "test_helper"

# PAY-03: Stripe's Connect notifications: signed, stored once, processed in the background,
# and nothing of the payload in the logs.
class Webhooks::StripeConnectTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @previous_secret = ENV["STRIPE_CONNECT_WEBHOOK_SECRET"]
    ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = "whsec_test"
    @gateway = use_fake_payment_gateway
    @business = businesses(:one)
    @account = as_business(@business) { PaymentAccount.create!(account_id: "acct_test1") }
  end

  teardown { ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = @previous_secret }

  def deliver(payload, signature)
    post stripe_connect_webhook_path, params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => signature }
  end

  def account_object(charges: true)
    { id: "acct_test1", country: "US", details_submitted: true, charges_enabled: charges, payouts_enabled: charges,
      email: "owner-private@example.com", business_profile: { name: "Secret name" },
      requirements: { currently_due: [], past_due: [], pending_verification: [], disabled_reason: nil } }
  end

  test "account.updated keeps the status in sync, once per event, without storing or logging personal details" do
    payload, signature = signed_connect_event("account.updated", account_object, id: "evt_1")
    log = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    perform_enqueued_jobs { deliver(payload, signature) }
    Rails.logger = previous_logger
    assert_response :ok
    assert_no_match(/owner-private|Secret name/, log.string)

    as_business(@business) { assert_equal "active", @account.reload.status }
    event = ConnectEvent.find_by!(event_id: "evt_1")
    assert_equal "processed", event.status
    assert_not event.data.key?("email")
    assert_not event.data.key?("business_profile")

    as_business(@business) { @account.update!(charges_enabled: false) }
    assert_no_enqueued_jobs { deliver(payload, signature) }
    assert_response :ok
    as_business(@business) { assert_not @account.reload.charges_enabled?, "a repeat isn't processed again" }
  end

  test "a bad signature, an unsigned body or a missing secret is refused" do
    payload, = signed_connect_event("account.updated", account_object)
    deliver(payload, "t=1,v1=nope")
    assert_response :bad_request
    _, signature = signed_connect_event("account.updated", account_object, secret: "whsec_other")
    deliver(payload, signature)
    assert_response :bad_request
    ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = nil
    deliver(*signed_connect_event("account.updated", account_object))
    assert_response :service_unavailable
    assert_equal 0, ConnectEvent.count
  end

  test "events for unknown accounts and types we don't use are ignored" do
    perform_enqueued_jobs do
      deliver(*signed_connect_event("account.updated", account_object, account: "acct_someone_else", id: "evt_2"))
      deliver(*signed_connect_event("payout.paid", { id: "po_1" }, id: "evt_3"))
    end
    assert_equal %w[ignored ignored], ConnectEvent.where(event_id: %w[evt_2 evt_3]).pluck(:status)
    as_business(@business) { assert_equal "onboarding_incomplete", @account.reload.status }
  end

  test "the business disconnecting Shadetree in Stripe marks the account disconnected" do
    perform_enqueued_jobs { deliver(*signed_connect_event("account.application.deauthorized", { id: "ca_123", object: "application" })) }
    as_business(@business) do
      assert_equal "provider", @account.reload.disconnected_reason
      assert_nil @business.reload.payment_account
    end
    assert_empty @gateway.calls_to(:disconnect)
  end

  test "a failed event is retried when Stripe delivers it again; old events are pruned" do
    payload, signature = signed_connect_event("account.updated", account_object, id: "evt_4")
    assert_enqueued_jobs(1, only: ProcessConnectEventJob) { deliver(payload, signature) }
    ConnectEvent.find_by!(event_id: "evt_4").finish!("failed", error: "RuntimeError: boom")
    perform_enqueued_jobs(only: ProcessConnectEventJob) { deliver(payload, signature) }
    assert_equal "processed", ConnectEvent.find_by!(event_id: "evt_4").status

    ConnectEvent.find_by!(event_id: "evt_4").update!(created_at: 91.days.ago)
    PruneConnectEventsJob.perform_now
    assert_not ConnectEvent.exists?(event_id: "evt_4")
  end
end
