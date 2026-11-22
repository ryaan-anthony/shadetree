# Stands in for Stripe in tests (PAY-03, PAY-04): PaymentGateway.current is swapped for one of
# these, which records each call and answers like Stripe would, so tests never reach Stripe.
#
#   gateway = use_fake_payment_gateway
#   gateway.accounts["acct_1"] = { "id" => "acct_1", "charges_enabled" => true, ... }
#   gateway.fail_next!("Your card was declined.")
class FakePaymentGateway
  attr_reader :calls, :accounts, :payments, :completed_sessions

  def initialize(configured: true)
    @configured = configured
    @calls = []
    @accounts = {}
    @payments = {}
    @completed_sessions = []
    @failure = nil
    @counter = 0
  end

  def configured? = @configured

  def fail_next!(message = "Stripe couldn't be reached.") = @failure = message

  def calls_to(name) = calls.select { _1.first == name }

  def create_account(business_uid:)
    record(:create_account, business_uid)
    id = "acct_test#{@counter += 1}"
    accounts[id] = { "id" => id, "country" => "US", "details_submitted" => false, "charges_enabled" => false, "payouts_enabled" => false,
                     "requirements" => { "currently_due" => [ "business_type" ], "past_due" => [], "pending_verification" => [] } }
  end

  def retrieve_account(account_id)
    record(:retrieve_account, account_id)
    accounts.fetch(account_id) { raise PaymentGateway::Error, "No such account: #{account_id}" }
  end

  def onboarding_url(account_id, return_url:, refresh_url:)
    record(:onboarding_url, account_id, return_url:, refresh_url:)
    "https://connect.stripe.com/setup/s/#{account_id}/test"
  end

  def disconnect(account_id)
    record(:disconnect, account_id)
    true
  end

  def create_checkout_session(account_id, params, idempotency_key: nil)
    record(:create_checkout_session, account_id, params, idempotency_key:)
    id = "cs_test_#{@counter += 1}"
    { "id" => id, "url" => "https://checkout.stripe.com/c/pay/#{id}" }
  end

  def expire_checkout_session(account_id, session_id)
    record(:expire_checkout_session, account_id, session_id)
    completed_sessions.include?(session_id) ? "complete" : "expired"
  end

  def payment_details(account_id, payment_intent_id)
    record(:payment_details, account_id, payment_intent_id)
    payments.fetch(payment_intent_id) { { "charge_id" => "ch_for_#{payment_intent_id}", "brand" => "visa", "last4" => "4242" } }
  end

  private

  def record(name, *args, **options)
    if (message = @failure)
      @failure = nil
      raise PaymentGateway::Error, message
    end
    calls << [ name, *args, options ].reject { _1 == {} }
  end
end

# Swaps the fake in for one test.
module FakePaymentGatewayHelper
  # Called twice in one test (setup, then again with options), the gateway from before the
  # first call is the one put back: remembering the first fake instead leaked it into every
  # later test (a configured gateway adds Home's "Get paid online" step, for one).
  def use_fake_payment_gateway(**options)
    unless @restore_payment_gateway
      previous = PaymentGateway.instance_variable_get(:@current)
      @restore_payment_gateway = -> { PaymentGateway.current = previous }
    end
    PaymentGateway.current = FakePaymentGateway.new(**options)
  end

  def after_teardown
    @restore_payment_gateway&.call
    @restore_payment_gateway = nil
    super
  end

  # A Stripe Event as it arrives, signed with the Connect webhook secret.
  def signed_connect_event(type, object, account: "acct_test1", id: "evt_#{SecureRandom.hex(8)}", secret: ENV.fetch("STRIPE_CONNECT_WEBHOOK_SECRET", "whsec_test"))
    payload = { id:, object: "event", type:, account:, livemode: false, created: Time.current.to_i, data: { object: } }.to_json
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    [ payload, Stripe::Webhook::Signature.generate_header(timestamp, signature) ]
  end
end

ActiveSupport.on_load(:active_support_test_case) { include FakePaymentGatewayHelper }
