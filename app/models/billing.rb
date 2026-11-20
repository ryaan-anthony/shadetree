# Subscription billing (BIL-04, ADR 0022): Shadetree's own revenue, through Stripe's hosted
# Checkout and customer portal. This module holds the settings and the price lookup; the
# subscription state lives in Subscription, and every call to Stripe goes through StripeGateway.
module Billing
  PRICE_CACHE_TTL = 1.hour

  def self.gateway = StripeGateway.current
  def self.configured? = gateway.configured?
  def self.live_mode? = Stripe.api_key.to_s.include?("_live_")

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

  # [plan, interval] for a Stripe price: from its product ("shadetree_<plan>") and recurring
  # interval, which outlive the lookup key when a price is replaced.
  def self.plan_for_price(price)
    return [ nil, nil ] unless price

    product = price.product.respond_to?(:id) ? price.product.id : price.product.to_s
    interval = Plan::INTERVALS.key(price.recurring&.interval)
    plan = Plan.find_by(key: product.delete_prefix("shadetree_")) if product.start_with?("shadetree_")
    plan ? [ plan, interval ] : Array(Plan.for_lookup_key(price.lookup_key)).then { _1.any? ? _1 : [ nil, interval ] }
  end

  # Cancels every subscription the business's Stripe customer still has, at once (OPS-04 deleting
  # a business, ACC-06 closing one). Raises if Stripe can't be reached, so the caller can retry.
  def self.cancel_subscriptions!(business)
    return [] unless business.stripe_customer_id

    gateway.customer_subscriptions(business.stripe_customer_id).filter_map do |subscription|
      next if %w[canceled incomplete_expired].include?(subscription.status)

      gateway.cancel_subscription(subscription.id).id
    end
  end

  def self.forget_prices(keys) = keys.each { Rails.cache.delete([ "stripe-price", _1 ]) }
end
