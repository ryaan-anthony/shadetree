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
  # the app says payments aren't available rather than failing.
  def configured? = ENV["STRIPE_SECRET_KEY"].present?

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
  # and its history. An account that's already disconnected counts as done.
  def disconnect(account_id)
    call { ::Stripe::OAuth.deauthorize({ client_id: ENV.fetch("STRIPE_CONNECT_CLIENT_ID"), stripe_user_id: account_id }) }
    true
  rescue Error => error
    raise unless error.cause.is_a?(::Stripe::OAuth::InvalidClientError)

    true
  end

  # A hosted Checkout page on the business's account (a direct charge: the business is the
  # merchant of record). Returns the session's "id" and "url".
  def create_checkout_session(account_id, params, idempotency_key: nil)
    call { ::Stripe::Checkout::Session.create(params, { stripe_account: account_id, idempotency_key: }.compact) }.slice("id", "url")
  end

  # How a payment was made, for the receipt: card brand and last four, and the wallet if any.
  def payment_details(account_id, payment_intent_id)
    intent = call { ::Stripe::PaymentIntent.retrieve({ id: payment_intent_id, expand: [ "latest_charge" ] }, { stripe_account: account_id }) }
    charge = intent["latest_charge"].is_a?(Hash) ? intent["latest_charge"] : {}
    card = charge.dig("payment_method_details", "card") || {}
    { "charge_id" => charge["id"], "brand" => card["brand"], "last4" => card["last4"], "wallet" => card.dig("wallet", "type") }.compact
  end

  private

  def call
    result = yield
    result.respond_to?(:to_hash) ? result.to_hash.deep_stringify_keys : result
  rescue ::Stripe::StripeError, KeyError => error
    raise Error, error.is_a?(KeyError) ? "Stripe isn't fully set up (#{error.key} is missing)." : (error.message.presence || "Stripe couldn't be reached.")
  end
end
