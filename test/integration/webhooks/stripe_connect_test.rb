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

  # Makes ConnectEventHandler fail (as a database blip would) while the block runs.
  def with_failing_handler
    original = ConnectEventHandler.method(:handle)
    ConnectEventHandler.define_singleton_method(:handle) { |_event| raise ActiveRecord::ConnectionFailed, "database went away" }
    yield
  ensure
    ConnectEventHandler.define_singleton_method(:handle, original)
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

  test "a failing event is retried by its job with backoff, then by the sweeper, and given up on with one report after 8 tries" do
    with_failing_handler do
      perform_enqueued_jobs(only: ProcessConnectEventJob) { deliver(*signed_connect_event("account.updated", account_object, id: "evt_5")) }
    end
    assert_response :ok, "Stripe gets its 200 either way"
    event = ConnectEvent.find_by!(event_id: "evt_5")
    assert_equal [ "failed", 5 ], [ event.status, event.attempts ], "the job's retries ran out quietly"
    assert_match "database went away", event.error

    RetryConnectEventsJob.perform_now
    assert_equal 5, event.reload.attempts, "the sweeper waits 10 minutes since the last try"
    with_failing_handler do
      2.times do
        event.update_columns(updated_at: 11.minutes.ago)
        assert_no_error_reported { RetryConnectEventsJob.perform_now }
      end
      event.update_columns(updated_at: 11.minutes.ago)
      assert_error_reported(ActiveRecord::ConnectionFailed) { RetryConnectEventsJob.perform_now }
    end
    assert_equal [ "failed", 8 ], [ event.reload.status, event.attempts ]
    event.update_columns(updated_at: 11.minutes.ago)
    assert_no_error_reported { RetryConnectEventsJob.perform_now }
    assert_equal 8, event.reload.attempts, "given up on"
    as_business(@business) { assert_equal "onboarding_incomplete", @account.reload.status }
    ConnectEvent.receive!(JSON.parse(signed_connect_event("account.updated", account_object, id: "evt_5").first))
    assert_equal 8, event.reload.attempts, "a redelivery doesn't restart it either"
  end

  test "an event stored but never processed (its job was lost) is picked up by the sweeper" do
    deliver(*signed_connect_event("account.updated", account_object, id: "evt_6")) # the job is enqueued, never run
    event = ConnectEvent.find_by!(event_id: "evt_6")
    RetryConnectEventsJob.perform_now
    assert_equal "received", event.reload.status
    event.update_columns(updated_at: 11.minutes.ago)
    RetryConnectEventsJob.perform_now
    assert_equal [ "processed", 1 ], [ event.reload.status, event.attempts ]
    as_business(@business) { assert_equal "active", @account.reload.status }
  end

  test "events from the other mode are ignored, by the job and the sweeper" do
    payload = JSON.parse(signed_connect_event("account.updated", account_object, id: "evt_7").first).merge("livemode" => true).to_json
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.generate_header(timestamp, Stripe::Webhook::Signature.compute_signature(timestamp, payload, "whsec_test"))
    perform_enqueued_jobs { deliver(payload, signature) }
    assert_equal "ignored", ConnectEvent.find_by!(event_id: "evt_7").status
    as_business(@business) { assert_equal "onboarding_incomplete", @account.reload.status }

    ConnectEvent.find_by!(event_id: "evt_7").update_columns(status: "received", updated_at: 11.minutes.ago)
    RetryConnectEventsJob.perform_now
    assert_equal "ignored", ConnectEvent.find_by!(event_id: "evt_7").status
  end

  test "an older account.updated arriving late doesn't overwrite a newer status" do
    perform_enqueued_jobs do
      deliver(*signed_connect_event("account.updated", account_object, id: "evt_new"))
      payload = JSON.parse(signed_connect_event("account.updated", account_object(charges: false), id: "evt_old").first).merge("created" => 1.hour.ago.to_i).to_json
      timestamp = Time.current
      deliver(payload, Stripe::Webhook::Signature.generate_header(timestamp, Stripe::Webhook::Signature.compute_signature(timestamp, payload, "whsec_test")))
    end
    assert_equal "processed", ConnectEvent.find_by!(event_id: "evt_old").status
    as_business(@business) { assert_equal "active", @account.reload.status }
  end
end
