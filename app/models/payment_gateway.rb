# The app's door to Stripe Connect (PAY-03, PAY-04): the businesses' own Stripe accounts, their
# onboarding, and the payments clients make to them. Everything else calls PaymentGateway.current
# and gets plain hashes back (string keys, as Stripe names them), never Stripe objects, so tests
# swap in a fake and never reach Stripe:
#
#   PaymentGateway.current = FakePaymentGateway.new   # test/support/fake_payment_gateway.rb
#
# Every Stripe failure comes out as PaymentGateway::Error, with a message safe to show.
class PaymentGateway
  class Error < StandardError; end

  class << self
    attr_writer :current

    def current = @current ||= new
  end

  # Online payments need the platform's secret key; without it (development, a fresh staging)
  # the app says payments aren't available rather than failing. As StripeGateway (BIL-04) asks.
  def configured? = ::Stripe.api_key.present?

  # Live keys mean live mode; events from the other mode are ignored (ConnectEvent).
  def self.live_mode? = ::Stripe.api_key.to_s.start_with?("sk_live_", "rk_live_")

  # A new Standard account for a business: Stripe asks the business for everything else during
  # onboarding. US only at launch (PAY-03).
  def create_account(business_uid:)
    call { ::Stripe::Account.create(type: "standard", country: "US", metadata: { shadetree_business: business_uid }) }
  end

  def retrieve_account(account_id) = call { ::Stripe::Account.retrieve(account_id) }

  # A one-time link into Stripe's hosted onboarding (it also collects anything Stripe needs later).
  def onboarding_url(account_id, return_url:, refresh_url:)
    call { ::Stripe::AccountLink.create(account: account_id, type: "account_onboarding", return_url:, refresh_url:) }.fetch("url")
  end

  # Ends the platform's access to the account. The business keeps its Stripe account, its money
  # and its history. An account that's no longer connected counts as done; any other refusal
  # (a wrong client id, the other mode's key, an account Stripe won't let us deauthorize) raises.
  def disconnect(account_id)
    call { ::Stripe::OAuth.deauthorize({ client_id: ENV.fetch("STRIPE_CONNECT_CLIENT_ID"), stripe_user_id: account_id }) }
    true
  rescue Error => error
    raise unless self.class.already_disconnected?(error.cause)

    true
  end

  # Stripe's answer for an account that isn't connected to the platform (any more).
  def self.already_disconnected?(error)
    error.is_a?(::Stripe::OAuth::InvalidClientError) && error.message.to_s.match?(/not connected to|already (been )?deauthorized/i)
  end

  # A hosted Checkout page on the business's account (a direct charge: the business is the
  # merchant of record). Returns the session's "id" and "url".
  def create_checkout_session(account_id, params, idempotency_key: nil)
    call { ::Stripe::Checkout::Session.create(params, { stripe_account: account_id, idempotency_key: }.compact) }.slice("id", "url")
  end

  # Closes an open Checkout page so it can't be paid. Returns the session's status after:
  # "expired", or "complete" when the client already paid (too late to close it).
  def expire_checkout_session(account_id, session_id)
    options = { stripe_account: account_id }
    call { ::Stripe::Checkout::Session.expire(session_id, {}, options) }.fetch("status")
  rescue Error => error
    raise unless error.cause.is_a?(::Stripe::InvalidRequestError)

    call { ::Stripe::Checkout::Session.retrieve(session_id, options) }.fetch("status")
  end

  # A payment's charge as PAY-04 uses it: how it was paid (card brand and last four, the wallet
  # if any), when, what's been refunded and any dispute ({ "status", "amount" }), and the
  # PaymentIntent's metadata (whose payment it is).
  def payment_details(account_id, payment_intent_id)
    options = { stripe_account: account_id }
    intent = call { ::Stripe::PaymentIntent.retrieve({ id: payment_intent_id, expand: [ "latest_charge" ] }, options) }
    charge = intent["latest_charge"].is_a?(Hash) ? intent["latest_charge"] : {}
    card = charge.dig("payment_method_details", "card") || {}
    dispute = (call { ::Stripe::Dispute.list({ payment_intent: payment_intent_id, limit: 1 }, options) }["data"] || []).first if charge["disputed"]
    { "charge_id" => charge["id"], "brand" => card["brand"], "last4" => card["last4"], "wallet" => card.dig("wallet", "type"),
      "created" => charge["created"], "amount_refunded" => charge["amount_refunded"], "metadata" => intent["metadata"] || {},
      "dispute" => dispute&.slice("status", "amount") }.compact
  end

  private

  def call
    result = yield
    result.respond_to?(:to_hash) ? result.to_hash.deep_stringify_keys : result
  rescue ::Stripe::StripeError, KeyError => error
    raise Error, error.is_a?(KeyError) ? "Stripe isn't fully set up (#{error.key} is missing)." : (error.message.presence || "Stripe couldn't be reached.")
  end
end
