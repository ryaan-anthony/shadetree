# Sending an Owner to Stripe's hosted pages (BIL-04, ADR 0021), and back. Each method returns the
# URL to redirect to.
#
#   checkout = Billing::Checkout.new(business, plan_url: "https://…/admin/plan", return_url: "https://…/admin/plan/billing/done")
#   checkout.choose(plan, "yearly")   # Checkout for a new subscription, or the portal to confirm a switch
#   checkout.portal                   # card, invoices, plan and interval, cancelling
#   checkout.portal(flow: :payment)   # straight to updating the card
#   checkout.complete!(session_id)    # back from Checkout: applies the new subscription at once
class Billing::Checkout
  class Unavailable < StandardError; end

  def initialize(business, plan_url:, return_url:)
    @business = business
    @plan_url = plan_url
    @return_url = return_url
  end

  def choose(plan, interval)
    subscription = Tenancy.with_business(@business) { @business.subscription }
    if subscription&.live?
      return portal(flow: :cancel) if plan.free?

      switch(subscription, plan, interval)
    else
      raise ArgumentError, "#{plan.key} has no #{interval} price" unless plan.offers?(interval)

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

  private

  def gateway = Billing.gateway

  attr_reader :plan_url

  def price_id(plan, interval) = Billing.price_id(plan, interval) || raise(Unavailable, "no Stripe price for #{plan.lookup_key(interval)}")

  def new_subscription(plan, interval)
    session = gateway.create_checkout_session(
      mode: "subscription", customer: customer_id, client_reference_id: @business.uid,
      line_items: [ { price: price_id(plan, interval), quantity: 1 } ],
      success_url: "#{@return_url}?session_id={CHECKOUT_SESSION_ID}", cancel_url: plan_url,
      subscription_data: { metadata: { business_uid: @business.uid } }, metadata: { business_uid: @business.uid },
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
  # only: Checkout collects the billing email. Changing the Owner changes nothing here.
  def customer_id
    @business.stripe_customer_id || @business.with_lock do
      @business.stripe_customer_id || begin
        customer = gateway.create_customer({ name: @business.name, metadata: { business_uid: @business.uid } },
                                           idempotency_key: "shadetree-customer-#{@business.uid}")
        @business.update_columns(stripe_customer_id: customer.id)
        customer.id
      end
    end
  end
end
