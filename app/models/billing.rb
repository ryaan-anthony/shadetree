# Subscription billing (BIL-04, ADR 0022): Shadetree's own revenue, through Stripe's hosted
# Checkout and customer portal. This module holds the settings and the price lookup; the
# subscription state lives in Subscription, and every call to Stripe goes through StripeGateway.
module Billing
  PRICE_CACHE_TTL = 1.hour

  def self.gateway = StripeGateway.current
  def self.configured? = gateway.configured?

  # Stripe Tax on our subscriptions (09-billing open question 5, recommendation accepted). It
  # needs Stripe Tax turned on in the Stripe account; STRIPE_AUTOMATIC_TAX=false turns it off.
  def self.automatic_tax? = ENV.fetch("STRIPE_AUTOMATIC_TAX", "true") != "false"

  # The Stripe price id for a plan and interval, found by lookup key and cached (nil until
  # bin/rails stripe:sync_plans has made it).
  def self.price_id(plan, interval)
    key = plan.lookup_key(interval)
    Rails.cache.fetch([ "stripe-price", key ], expires_in: PRICE_CACHE_TTL, skip_nil: true) do
      gateway.prices_for_lookup_keys([ key ]).first&.id
    end
  end

  def self.forget_prices(keys) = keys.each { Rails.cache.delete([ "stripe-price", _1 ]) }
end
