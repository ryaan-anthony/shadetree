# Sending an Owner to Stripe's hosted pages (BIL-04, ADR 0022), and back. Each method returns the
# URL to redirect to.
#
#   checkout = Billing::Checkout.new(business, plan_url: "https://…/admin/plan", return_url: "https://…/admin/plan/billing/done")
#   checkout.choose(plan, "yearly")   # Checkout for a new subscription, or the portal to confirm a switch
#   checkout.portal                   # card, invoices, plan and interval, cancelling
#   checkout.portal(flow: :payment)   # straight to updating the card
#   checkout.complete!(session_id)    # back from Checkout: applies the new subscription at once
class Billing::Checkout
  class Unavailable < StandardError; end
  # The plan or interval can't be chosen (unknown, hidden, no such price, Free with nothing to cancel).
  class NotOffered < StandardError; end

  def initialize(business, plan_url:, return_url:)
    @business = business
    @plan_url = plan_url
    @return_url = return_url
  end

  def choose(plan, interval)
    raise NotOffered unless plan && Plan::INTERVALS.key?(interval.to_s) && (plan.public || plan == @business.plan)

    subscription = live_subscription
    if subscription
      return portal(flow: :cancel) if plan.free?
      raise NotOffered unless plan.offers?(interval)

      switch(subscription, plan, interval)
    else
      raise NotOffered unless plan.offers?(interval)

      new_subscription(plan, interval)
    end
  end

  def portal(flow: nil)
    subscription = Tenancy.with_business(@business) { @business.subscription }
    flow_data =
      case flow
      when :payment then { type: "payment_method_update" }
      when :cancel then subscription&.live? && { type: "subscription_cancel", subscription_cancel: { subscription: subscription.stripe_subscription_id } }
      end
    flow_data = flow_data.merge(after_completion: { type: "redirect", redirect: { return_url: plan_url } }) if flow_data
    session = gateway.create_portal_session({ customer: customer_id, return_url: plan_url, configuration: Billing::PlanSync.portal_configuration_id, flow_data: flow_data || nil }.compact)
    session.url
  end

  # Back from Checkout: the subscription it made is applied now, so the new plan shows at once
  # (the webhook then finds nothing to change). Returns the subscription, or nil if it isn't
  # finished or isn't this business's.
  def complete!(session_id)
    return unless @business.stripe_customer_id && session_id.to_s.start_with?("cs_")

    session = gateway.retrieve_checkout_session(session_id.to_s)
    return unless session.customer.to_s == @business.stripe_customer_id && session.status == "complete"

    subscription = session.subscription.respond_to?(:id) ? session.subscription.id : session.subscription
    subscription && Billing::SubscriptionSync.refresh!(@business, subscription)
  end

  # BIL-05: subscribing during the business's trial keeps the rest of it (billing starts when it
  # ends) if at least TRIAL_KEPT_MIN is left, Stripe's minimum; otherwise the trial ends on paying.
  TRIAL_KEPT_MIN = 48.hours

  def self.trial_kept_until(business, at: Time.current)
    ends = business.trial_ends_at
    ends if business.billing_status == "trialing" && ends && ends >= at + TRIAL_KEPT_MIN
  end

  private

  def gateway = Billing.gateway

  # The live subscription mirrored here or, failing that, one Stripe has for the customer that
  # hasn't reached us yet (it's mirrored now), so a second Checkout never starts a second one.
  def live_subscription
    mirrored = Tenancy.with_business(@business) { @business.reload_subscription }
    return mirrored if mirrored&.live?
    return unless @business.stripe_customer_id

    remote = gateway.customer_subscriptions(@business.stripe_customer_id).find { Subscription::LIVE_STATUSES.include?(_1.status) }
    remote && Billing::SubscriptionSync.refresh!(@business, remote.id)
  end

  attr_reader :plan_url

  def price_id(plan, interval) = Billing.price_id(plan, interval) || raise(Unavailable, "no Stripe price for #{plan.lookup_key(interval)}")

  def new_subscription(plan, interval)
    session = gateway.create_checkout_session(
      mode: "subscription", customer: customer_id, client_reference_id: @business.uid,
      line_items: [ { price: price_id(plan, interval), quantity: 1 } ],
      success_url: "#{@return_url}?session_id={CHECKOUT_SESSION_ID}", cancel_url: plan_url,
      subscription_data: { metadata: { business_uid: @business.uid }, trial_end: self.class.trial_kept_until(@business)&.to_i }.compact,
      metadata: { business_uid: @business.uid },
      automatic_tax: { enabled: Billing.automatic_tax? }, customer_update: { address: "auto", name: "auto" }
    )
    session.url
  end

  # A live subscription changes in the portal, on a page confirming the new plan and its prorated
  # cost (the portal only offers our public plans' prices).
  def switch(subscription, plan, interval)
    remote = gateway.retrieve_subscription(subscription.stripe_subscription_id)
    item = remote.items.data.first
    session = gateway.create_portal_session(
      customer: customer_id, return_url: plan_url, configuration: Billing::PlanSync.portal_configuration_id,
      flow_data: { type: "subscription_update_confirm",
                   subscription_update_confirm: { subscription: remote.id, items: [ { id: item.id, price: price_id(plan, interval), quantity: 1 } ] },
                   after_completion: { type: "redirect", redirect: { return_url: plan_url } } }
    )
    session.url
  end

  # One Stripe customer per business, made the first time it's needed, with the business's name
  # only: Checkout collects the billing email. Stripe is called without a lock; the idempotency
  # key makes two requests at once get the same customer. Changing the Owner changes nothing here.
  def customer_id
    return @business.stripe_customer_id if @business.stripe_customer_id

    customer = gateway.create_customer({ name: @business.name, metadata: { business_uid: @business.uid } },
                                       idempotency_key: "shadetree-customer-#{@business.uid}")
    Business.where(id: @business.id, stripe_customer_id: nil).update_all(stripe_customer_id: customer.id, updated_at: Time.current)
    @business.stripe_customer_id = Business.where(id: @business.id).pick(:stripe_customer_id)
  end
end
