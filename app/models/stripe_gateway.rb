# The one place the app calls Stripe's API. Each method is a thin call that returns Stripe's
# objects; what they mean for a business lives in Billing. Tests swap in FakeStripeGateway
# (test/support/fake_stripe_gateway.rb) through StripeGateway.current, so no test reaches
# api.stripe.com.
#
#   StripeGateway.current.retrieve_subscription("sub_123")
class StripeGateway
  class NotConfigured < StandardError; end

  class << self
    attr_writer :current

    def current = @current ||= new
  end

  def configured? = Stripe.api_key.present?

  # Plans as products and prices (bin/rails stripe:sync_plans).
  def retrieve_product(id)
    call { Stripe::Product.retrieve(id) }
  rescue Stripe::InvalidRequestError => error
    raise unless error.code == "resource_missing"
  end

  def create_product(params) = call { Stripe::Product.create(params) }
  def update_product(id, params) = call { Stripe::Product.update(id, params) }
  def prices_for_lookup_keys(keys) = call { Stripe::Price.list(lookup_keys: keys, active: true, limit: 100).data }
  def create_price(params) = call { Stripe::Price.create(params) }
  def update_price(id, params) = call { Stripe::Price.update(id, params) }
  def portal_configurations = call { Stripe::BillingPortal::Configuration.list(active: true, limit: 100).data }
  def create_portal_configuration(params) = call { Stripe::BillingPortal::Configuration.create(params) }
  def update_portal_configuration(id, params) = call { Stripe::BillingPortal::Configuration.update(id, params) }

  # Customers, checkout and the customer portal.
  def create_customer(params, idempotency_key:) = call { Stripe::Customer.create(params, { idempotency_key: }) }
  def create_checkout_session(params) = call { Stripe::Checkout::Session.create(params) }
  def retrieve_checkout_session(id) = call { Stripe::Checkout::Session.retrieve(id) }
  def create_portal_session(params) = call { Stripe::BillingPortal::Session.create(params) }

  # Subscriptions and their invoices.
  def retrieve_subscription(id) = call { Stripe::Subscription.retrieve(id) }
  def customer_subscriptions(customer) = call { Stripe::Subscription.list(customer:, status: "all", limit: 100).data }
  def update_subscription(id, params) = call { Stripe::Subscription.update(id, params) }
  def cancel_subscription(id) = call { Stripe::Subscription.cancel(id) }
  def retrieve_invoice(id) = call { Stripe::Invoice.retrieve(id) }

  private

  def call
    raise NotConfigured, "STRIPE_SECRET_KEY isn't set" unless configured?

    yield
  end
end
