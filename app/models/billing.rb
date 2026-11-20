# Subscription billing (BIL-04, ADR 0022): Shadetree's own revenue, through Stripe's hosted
# Checkout and customer portal. This module holds the settings and the price lookup; the
# subscription state lives in Subscription, and every call to Stripe goes through StripeGateway.
module Billing
  PRICE_CACHE_TTL = 1.hour

  def self.gateway = StripeGateway.current

  # BIL-05 settings (config/application.rb).
  def self.settings = Rails.configuration.x.billing
  def self.trial_days = settings.trial_days.to_i
  def self.trial_plan = trial_days.positive? ? Plan.find_by(key: settings.trial_plan) : nil
  def self.grace_period = settings.grace_days.to_i.days

  # Why a business moved to Free (Billing::PlanResolver), in words.
  LAPSES = {
    "trial_ended" => "the trial ended", "subscription_ended" => "the subscription ended",
    "unpaid" => "the renewal wasn't paid within the grace period", "comp_ended" => "the comped plan ended"
  }.freeze
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

  # OPS-04: while a business waits to be deleted, its live subscriptions end at the end of the
  # paid period (marked in Stripe's metadata); cancelling the deletion undoes only what this
  # set, not a cancellation the Owner chose. Returns the subscription ids changed.
  DELETION_MARK = "shadetree_deletion"

  def self.cancel_for_deletion!(business, cancel: true)
    return [] unless business.stripe_customer_id

    changed = gateway.customer_subscriptions(business.stripe_customer_id).filter_map do |subscription|
      next unless Subscription::LIVE_STATUSES.include?(subscription.status)

      marked = subscription.metadata&.[](DELETION_MARK) == "1"
      if cancel && !subscription.cancel_at_period_end
        gateway.update_subscription(subscription.id, cancel_at_period_end: true, metadata: { DELETION_MARK => "1" })
      elsif !cancel && marked
        gateway.update_subscription(subscription.id, cancel_at_period_end: false, metadata: { DELETION_MARK => "" })
      end&.id
    end
    changed.each { Billing::SubscriptionSync.refresh!(business, _1) }
    changed
  end

  def self.forget_prices(keys) = keys.each { Rails.cache.delete([ "stripe-price", _1 ]) }
end
