# Sets Stripe up from the Plan table (bin/rails stripe:sync_plans), the same way in test and live
# mode, and safe to run again: a product per paid plan (id "shadetree_<key>"), a monthly and a
# yearly price found by lookup key, and the customer portal's settings. A price whose amount
# changed is replaced (prices can't be edited): the new one takes the lookup key, the old one is
# archived, and existing subscribers stay on it until they change plan. Returns what it did, one
# line each.
class Billing::PlanSync
  PORTAL_KEY = "shadetree_default"
  # Prices are before tax; Stripe Tax adds sales tax where it applies, as the plan and pricing
  # pages say (09-billing open question 5). A price made without it is replaced on the next run.
  TAX_BEHAVIOR = "exclusive"

  attr_reader :log

  def initialize(gateway: Billing.gateway, return_url: nil)
    @gateway = gateway
    @return_url = return_url
    @log = []
  end

  def run!
    Plan.order(:position, :id).each { sync_plan(_1) }
    sync_portal
    log
  end

  # The portal's settings, found by metadata (Stripe has no lookup key for them).
  def self.portal_configuration_id(gateway: Billing.gateway)
    Rails.cache.fetch("stripe-portal-configuration", expires_in: Billing::PRICE_CACHE_TTL, skip_nil: true) do
      gateway.portal_configurations.find { _1.metadata&.[]("shadetree") == PORTAL_KEY }&.id
    end
  end

  private

  attr_reader :gateway

  def sync_plan(plan)
    product = gateway.retrieve_product(plan.stripe_product_id)
    if plan.free?
      if product&.active
        gateway.update_product(product.id, active: false)
        log << "#{plan.key}: free now, product archived"
      end
      return
    end

    attributes = { name: "Shadetree #{plan.name}", description: plan.description.presence, metadata: { plan_key: plan.key } }.compact
    if product.nil?
      gateway.create_product(attributes.merge(id: plan.stripe_product_id))
      log << "#{plan.key}: product created"
    elsif product.name != attributes[:name] || product.description != attributes[:description] || !product.active
      gateway.update_product(product.id, attributes.merge(active: true))
      log << "#{plan.key}: product updated"
    end
    Plan::INTERVALS.each_key { sync_price(plan, _1) }
  end

  def sync_price(plan, interval)
    key = plan.lookup_key(interval)
    existing = gateway.prices_for_lookup_keys([ key ]).first
    unless plan.offers?(interval)
      return unless existing

      gateway.update_price(existing.id, active: false, lookup_key: "")
      Billing.forget_prices([ key ])
      return log << "#{key}: archived (no #{interval} price)"
    end
    return if existing && same_price?(existing, plan, interval)

    gateway.create_price(product: plan.stripe_product_id, currency: plan.currency.downcase, unit_amount: plan.price_cents(interval),
                         recurring: { interval: Plan::INTERVALS.fetch(interval) }, tax_behavior: TAX_BEHAVIOR, lookup_key: key, transfer_lookup_key: true,
                         nickname: "#{plan.name} #{interval}", metadata: { plan_key: plan.key, interval: })
    gateway.update_price(existing.id, active: false) if existing
    Billing.forget_prices([ key ])
    log << "#{key}: #{existing ? "new price (the old one is archived)" : "price created"}"
  end

  def same_price?(price, plan, interval)
    price.unit_amount == plan.price_cents(interval) && price.currency == plan.currency.downcase &&
      price.recurring&.interval == Plan::INTERVALS.fetch(interval) && price.product.to_s == plan.stripe_product_id &&
      price.tax_behavior == TAX_BEHAVIOR
  end

  # Owners can update their card, see invoices, switch between public paid plans and intervals
  # (prorated), and cancel at the end of the period. Hidden plans can't be chosen there.
  def sync_portal
    products = Plan.listed.reject(&:free?).filter_map do |plan|
      prices = Plan::INTERVALS.keys.filter_map { Billing.price_id(plan, _1) if plan.offers?(_1) }
      { product: plan.stripe_product_id, prices: } if prices.any?
    end
    params = {
      business_profile: { headline: "Shadetree billing", privacy_policy_url: "https://getshadetree.com/privacy",
                          terms_of_service_url: "https://getshadetree.com/terms" },
      features: {
        customer_update: { enabled: true, allowed_updates: %w[email address tax_id] },
        invoice_history: { enabled: true },
        payment_method_update: { enabled: true },
        subscription_cancel: { enabled: true, mode: "at_period_end" },
        subscription_update: { enabled: products.any?, default_allowed_updates: products.any? ? %w[price] : [],
                               products: products.presence, proration_behavior: "create_prorations" }.compact
      },
      default_return_url: @return_url
    }.compact
    existing = gateway.portal_configurations.find { _1.metadata&.[]("shadetree") == PORTAL_KEY }
    if existing
      gateway.update_portal_configuration(existing.id, params)
      log << "customer portal: settings updated"
    else
      gateway.create_portal_configuration(params.merge(metadata: { shadetree: PORTAL_KEY }))
      log << "customer portal: settings created"
    end
    Rails.cache.delete("stripe-portal-configuration")
  end
end
