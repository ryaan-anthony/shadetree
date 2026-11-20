# BIL-04: an in-memory stand-in for StripeGateway, so no test calls Stripe. Every test starts
# with a fresh one (StripeGateway.current); reach it as `stripe` in tests. Objects are real
# Stripe::StripeObjects built from hashes, so code reads them as it reads Stripe's.
class FakeStripeGateway
  attr_reader :products, :prices, :customers, :checkout_sessions, :portal_sessions,
              :subscriptions, :invoices, :calls
  attr_accessor :fail_with, :configured

  def initialize
    @products, @customers, @checkout_sessions, @subscriptions, @invoices = {}, {}, {}, {}, {}
    @prices, @portal_configurations, @portal_sessions, @calls = [], [], [], []
    @configured = true
    @ids = Hash.new(0)
  end

  def configured? = configured

  def retrieve_product(id) = record(:retrieve_product, id) { products[id]&.then { object(_1) } }
  def create_product(params) = record(:create_product, params) { object(products[params[:id]] = { object: "product", active: true, **params }) }

  def update_product(id, params)
    record(:update_product, id, params) { object(products.fetch(id).merge!(params)) }
  end

  def prices_for_lookup_keys(keys)
    record(:prices_for_lookup_keys, keys) { prices.select { _1[:active] && keys.include?(_1[:lookup_key]) }.map { object(_1) } }
  end

  def create_price(params)
    record(:create_price, params) do
      prices.each { _1[:lookup_key] = nil if _1[:lookup_key] == params[:lookup_key] } if params[:transfer_lookup_key]
      price = { object: "price", id: next_id("price"), active: true, **params.except(:transfer_lookup_key) }
      prices << price
      object(price)
    end
  end

  def update_price(id, params)
    record(:update_price, id, params) do
      price = prices.find { _1[:id] == id }
      price.merge!(params)
      price[:lookup_key] = nil if params[:lookup_key] == ""
      object(price)
    end
  end

  def create_portal_configuration(params)
    record(:create_portal_configuration, params) { object(new_portal_configuration(params)) }
  end

  def update_portal_configuration(id, params)
    record(:update_portal_configuration, id, params) { object(@portal_configurations.find { _1[:id] == id }.merge!(params)) }
  end

  def create_customer(params, idempotency_key:)
    record(:create_customer, params, idempotency_key) do
      existing = customers.values.find { _1[:idempotency_key] == idempotency_key }
      object(existing || (customers[id = next_id("cus")] = { object: "customer", id:, idempotency_key:, **params }))
    end
  end

  def create_checkout_session(params)
    record(:create_checkout_session, params) do
      id = next_id("cs")
      object(checkout_sessions[id] = { object: "checkout.session", id:, url: "https://checkout.stripe.com/c/pay/#{id}", status: "open", **params })
    end
  end

  def retrieve_checkout_session(id) = record(:retrieve_checkout_session, id) { object(checkout_sessions.fetch(id)) }

  def create_portal_session(params)
    record(:create_portal_session, params) do
      session = { object: "billing_portal.session", id: next_id("bps"), url: "https://billing.stripe.com/p/session/#{portal_sessions.size + 1}", **params }
      portal_sessions << session
      object(session)
    end
  end

  def retrieve_subscription(id) = record(:retrieve_subscription, id) { object(subscriptions.fetch(id)) }

  def customer_subscriptions(customer)
    record(:customer_subscriptions, customer) { subscriptions.values.select { _1[:customer] == customer }.map { object(_1) } }
  end

  def update_subscription(id, params) = record(:update_subscription, id, params) { object(subscriptions.fetch(id).merge!(params)) }

  def cancel_subscription(id)
    record(:cancel_subscription, id) { object(subscriptions.fetch(id).merge!(status: "canceled", canceled_at: Time.current.to_i, ended_at: Time.current.to_i)) }
  end

  def retrieve_invoice(id) = record(:retrieve_invoice, id) { object(invoices.fetch(id)) }

  # Test data: a subscription as Stripe would return it (the period lives on its item).
  def add_subscription(customer:, plan:, interval: "monthly", status: "active", id: next_id("sub"), period_start: Time.current,
                       cancel_at_period_end: false, metadata: {}, **extra)
    price = prices.find { _1[:lookup_key] == plan.lookup_key(interval) } || { id: "price_#{plan.key}_#{interval}", lookup_key: plan.lookup_key(interval) }
    period_end = period_start + (interval == "yearly" ? 1.year : 1.month)
    subscriptions[id] = {
      object: "subscription", id:, customer:, status:, cancel_at_period_end:, cancel_at: nil, canceled_at: nil, ended_at: nil,
      billing_cycle_anchor: period_start.to_i, start_date: period_start.to_i, trial_end: nil, metadata:, discounts: [], latest_invoice: nil,
      items: { object: "list", data: [ { object: "subscription_item", id: "si_#{id}", current_period_start: period_start.to_i,
                                         current_period_end: period_end.to_i, quantity: 1,
                                         price: { object: "price", id: price[:id], lookup_key: price[:lookup_key], product: plan.stripe_product_id, unit_amount: plan.price_cents(interval),
                                                  currency: plan.currency.downcase, recurring: { interval: Plan::INTERVALS.fetch(interval) } } } ] },
      **extra
    }
    id
  end

  def add_invoice(subscription:, status: "paid", amount: 1900, id: next_id("in"), **extra)
    sub = subscriptions.fetch(subscription)
    invoices[id] = { object: "invoice", id:, customer: sub[:customer], status:, amount_paid: status == "paid" ? amount : 0, amount_due: amount,
                     currency: "usd", number: "SHADE-#{id}", hosted_invoice_url: "https://invoice.stripe.com/i/#{id}", created: Time.current.to_i,
                     attempt_count: 1, billing_reason: "subscription_cycle",
                     parent: { type: "subscription_details", subscription_details: { subscription: } }, **extra }
    id
  end

  def call_names = calls.map(&:first)

  private

  def record(name, *args)
    raise fail_with if fail_with

    calls << [ name, *args ]
    yield
  end

  def new_portal_configuration(params)
    config = { object: "billing_portal.configuration", id: next_id("bpc"), active: true, **params }
    @portal_configurations << config
    config
  end

  def next_id(prefix) = "#{prefix}_test#{@ids[prefix] += 1}"

  def object(hash) = Stripe::Util.convert_to_stripe_object(hash.deep_dup, {})

  public

  # The gateway's own list (Stripe returns active ones).
  def portal_configurations = @portal_configurations.select { _1[:active] }.map { object(_1) }
end

module StripeTestHelpers
  extend ActiveSupport::Concern

  included do
    setup { StripeGateway.current = FakeStripeGateway.new }
    teardown { StripeGateway.current = nil }
  end

  def stripe = StripeGateway.current

  WEBHOOK_SECRET = "whsec_test_secret"

  # A Stripe event body, and the Stripe-Signature header Stripe would send with it.
  def stripe_event_json(type, object, id: "evt_#{SecureRandom.hex(8)}", created: Time.current)
    { id:, object: "event", api_version: Stripe.api_version, type:, created: created.to_i, livemode: false, data: { object: } }.to_json
  end

  def stripe_signature(payload, secret: WEBHOOK_SECRET, at: Time.current)
    Stripe::Webhook::Signature.generate_header(at, Stripe::Webhook::Signature.compute_signature(at, payload, secret))
  end

  # Gives a business a Stripe customer, as starting checkout does.
  def with_stripe_customer(business, id: "cus_#{business.uid}")
    business.update_columns(stripe_customer_id: id)
    id
  end
end

ActiveSupport.on_load(:active_support_test_case) { include StripeTestHelpers }
