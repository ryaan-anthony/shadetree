# The plan a business is on, worked out in one place from its billing state (ADR 0021): the
# subscription's plan while it's live (paying, trialing, or a failed renewal being retried),
# otherwise the default plan (Free). Every change of plan is written to the billing history.
# Call with the business locked; returns the plan.
#
#   Billing::PlanResolver.apply!(business)
class Billing::PlanResolver
  def self.apply!(business) = new(business).apply!

  def initialize(business)
    @business = business
  end

  def plan
    subscription = self.subscription
    subscription&.live? && subscription.plan ? subscription.plan : Plan.default!
  end

  def subscription = Tenancy.with_business(@business) { @business.subscription }

  def apply!
    target = plan
    subscription = self.subscription
    anchor = subscription&.live? ? subscription.billing_cycle_anchor : @business.billing_cycle_anchor
    return target if target == @business.plan && anchor == @business.billing_cycle_anchor

    from = @business.plan
    @business.update_columns(plan_id: target.id, billing_cycle_anchor: anchor, updated_at: Time.current)
    @business.association(:plan).target = target
    @business.reload_entitlements
    Tenancy.with_business(@business) { BillingEvent.record!("plan_changed", details: { "from" => from.name, "to" => target.name }) } if from != target
    target
  end
end
