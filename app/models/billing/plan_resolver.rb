# The plan a business is on, worked out in one place from its billing state (ADR 0022, BIL-05).
# In order:
#
# 1. A live Stripe subscription's plan: paying, Stripe trialing, cancelled but not yet at the end
#    of the paid period, or a failed renewal still within the grace period. It wins over a comp,
#    so what the business gets always matches what Stripe charges (operators can't comp a
#    business that has one, Ops::BillingController).
# 2. A plan an operator comped (OPS-04), until its end date if it has one.
# 3. The business's own trial (BIL-05), until it ends.
# 4. Otherwise the default plan (Free). Nothing is deleted; BIL-03's downgrade rules apply.
#
# It also keeps businesses.billing_status (for the operator directory) and billing_check_at
# (when this must run again because time alone changes the answer: a trial, comp, grace period
# or paid period ending). Every change of plan goes into the billing history; moving to Free
# emails the Owners. Call with the business locked; returns the plan.
#
#   Billing::PlanResolver.apply!(business)
class Billing::PlanResolver
  Outcome = Data.define(:plan, :status, :reason, :check_at)

  def self.apply!(business, at: Time.current) = new(business, at:).apply!

  def initialize(business, at: Time.current)
    @business = business
    @now = at
  end

  def subscription = @subscription ||= Tenancy.with_business(@business) { @business.reload_subscription }

  def outcome
    @outcome ||= from_subscription || comp || trial || Outcome.new(plan: Plan.default!, status: free_status, reason: lapse_reason, check_at: nil)
  end

  def plan = outcome.plan

  def apply!
    result = outcome
    sub = subscription
    anchor = sub&.live? ? sub.billing_cycle_anchor : @business.billing_cycle_anchor
    changes = { plan_id: result.plan.id, billing_cycle_anchor: anchor, billing_status: result.status, billing_check_at: result.check_at }
    current = changes.keys.to_h { [ _1, @business.public_send(_1) ] }
    return result.plan if current == changes

    from = @business.plan
    @business.update_columns(**changes, updated_at: @now)
    @business.association(:plan).target = result.plan
    @business.reload_entitlements
    if from != result.plan
      Tenancy.with_business(@business) do
        BillingEvent.record!("plan_changed", details: { "from" => from.name, "to" => result.plan.name, "note" => result.reason }.compact)
      end
      if result.plan.default && !from.free? && result.reason
        BillingMailer.notify_owners(@business, :moved_to_free, from_plan: from.name, reason: result.reason)
      end
    end
    result.plan
  end

  private

  def comp
    return unless @business.comp_plan && (@business.comp_ends_at.nil? || @business.comp_ends_at > @now)

    Outcome.new(plan: @business.comp_plan, status: "comped", reason: nil, check_at: @business.comp_ends_at)
  end

  def from_subscription
    sub = subscription
    return unless sub&.live? && sub.plan
    return if sub.cancel_at_period_end && sub.current_period_end && sub.current_period_end <= @now # Stripe's end hasn't reached us yet

    if sub.past_due?
      grace_ends = (sub.past_due_since || @now) + Billing.grace_period
      return if grace_ends <= @now

      return Outcome.new(plan: sub.plan, status: "past_due", reason: nil, check_at: grace_ends)
    end
    Outcome.new(plan: sub.plan, status: "active", reason: nil, check_at: (sub.current_period_end if sub.cancel_at_period_end))
  end

  def trial
    return unless @business.trial_plan && @business.trial_ends_at && @business.trial_ends_at > @now

    Outcome.new(plan: @business.trial_plan, status: "trialing", reason: nil, check_at: [ @business.trial_ends_at, next_reminder ].compact.min)
  end

  # When the next "your trial ends in N days" email is due (TrialReminders).
  def next_reminder
    Billing::TrialReminders::DAYS.filter_map do |days|
      at = Billing::TrialReminders.due_at(@business, days)
      at if at > @now && at < @business.trial_ends_at && (@business.trial_reminded_days.nil? || @business.trial_reminded_days > days)
    end.min
  end

  # Why a business is on Free, for the history and the email: whichever paid state ended last;
  # nil when it never had one.
  def lapse_reason
    sub = subscription
    ended = []
    ended << [ "unpaid", sub.past_due_since + Billing.grace_period ] if sub&.past_due? && sub.past_due_since
    ended << [ "subscription_ended", sub.ended_at || sub.current_period_end || sub.updated_at ] if sub && (!sub.live? || sub.cancel_at_period_end)
    ended << [ "comp_ended", @business.comp_ends_at ] if @business.comp_plan && @business.comp_ends_at
    ended << [ "trial_ended", @business.trial_ends_at ] if @business.trial_plan && @business.trial_ends_at
    ended.max_by(&:last)&.first
  end

  def free_status = subscription&.past_due? ? "past_due" : "free"
end
