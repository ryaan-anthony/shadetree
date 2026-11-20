# Mirrors a Stripe subscription onto its business (BIL-04, ADR 0021): the Subscription row, the
# billing history entries its changes mean, then the business's plan. Given the subscription as
# Stripe returns it now, so applying it twice, or after a newer event, changes nothing.
#
#   Billing::SubscriptionSync.refresh!(business, "sub_123")   # fetches it from Stripe first
#   Billing::SubscriptionSync.apply!(business, stripe_subscription)
#
# The business stays locked from fetching to saving, so two events processed at once can't
# apply an older state over a newer one.
class Billing::SubscriptionSync
  def self.apply!(business, stripe_subscription) = new(business) { stripe_subscription }.apply!
  def self.refresh!(business, id) = new(business) { Billing.gateway.retrieve_subscription(id) }.apply!

  def initialize(business, &fetch)
    @business = business
    @fetch = fetch
  end

  def apply!
    Tenancy.with_business(@business) do
      @business.with_lock do
        @remote = @fetch.call
        row = @business.subscription || @business.build_subscription
        if row.persisted? && row.stripe_subscription_id != @remote.id
          # An older subscription's late news never replaces a live one.
          return row if row.live? && !Subscription::LIVE_STATUSES.include?(@remote.status)

          row = @business.subscription # replaced below, keeping one row per business
        end
        before = row.attributes.slice(*%w[stripe_subscription_id status plan_id interval cancel_at_period_end])
        row.assign_attributes(attributes)
        record_changes(before, row)
        row.save!
        Billing::PlanResolver.apply!(@business)
        row
      end
    end
  end

  private

  def attributes
    item = @remote.items.data.first
    plan, interval = Billing.plan_for_price(item&.price)
    {
      stripe_subscription_id: @remote.id, status: @remote.status, plan:, interval:,
      current_period_start: time(item&.current_period_start), current_period_end: time(item&.current_period_end),
      cancel_at_period_end: @remote.cancel_at_period_end == true || @remote.cancel_at.present?,
      canceled_at: time(@remote.canceled_at), ended_at: time(@remote.ended_at), billing_cycle_anchor: time(@remote.billing_cycle_anchor)
    }
  end

  def record_changes(before, row)
    was_live = before["stripe_subscription_id"] == row.stripe_subscription_id && Subscription::LIVE_STATUSES.include?(before["status"])
    plan = { "plan" => row.plan&.name, "interval" => row.interval }
    if row.live? && !was_live
      event("subscribed", plan)
    elsif row.live? && (before["plan_id"] != row.plan_id || before["interval"] != row.interval)
      event("switched", plan)
    end
    if row.live? && row.cancel_at_period_end != before["cancel_at_period_end"] && (was_live || row.cancel_at_period_end)
      event(row.cancel_at_period_end ? "cancel_scheduled" : "cancel_withdrawn", "ends_on" => row.current_period_end&.to_date&.iso8601)
    end
    event("past_due", {}) if row.past_due? && before["status"] != "past_due"
    event("ended", "note" => row.status_label) if was_live && !row.live?
  end

  def event(kind, details) = BillingEvent.record!(kind, details:)

  def time(seconds) = seconds && Time.zone.at(seconds)
end
