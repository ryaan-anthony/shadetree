# Mirrors a Stripe subscription onto its business (BIL-04, ADR 0022): the Subscription row, the
# billing history entries its changes mean, then the business's plan. Given the subscription as
# Stripe returns it now, so applying it twice, or after a newer event, changes nothing.
#
#   Billing::SubscriptionSync.refresh!(business, "sub_123")   # fetches it from Stripe first
#   Billing::SubscriptionSync.apply!(business, stripe_subscription, fetched_at:)
#
# Stripe is called before any lock is taken. Each row remembers when the state it holds was
# fetched (synced_at), and a state fetched earlier than that is never applied, so two events
# processed at once can't put an older state over a newer one.
class Billing::SubscriptionSync
  # The subscription isn't this business's (another customer, or another business's metadata).
  class Mismatch < StandardError; end

  def self.refresh!(business, id)
    fetched_at = Time.current
    remote = Billing.gateway.retrieve_subscription(id)
    remote = other_live(business, remote) || remote unless Subscription::LIVE_STATUSES.include?(remote.status)
    apply!(business, remote, fetched_at:)
  end

  def self.apply!(business, remote, fetched_at: Time.current) = new(business, remote, fetched_at).apply!

  # When the subscription mirrored here has ended, another live one on the same customer (a
  # second checkout) takes its place rather than the business dropping to Free.
  def self.other_live(business, remote)
    return unless business.stripe_customer_id

    Billing.gateway.customer_subscriptions(business.stripe_customer_id)
           .find { _1.id != remote.id && Subscription::LIVE_STATUSES.include?(_1.status) }
  end

  def initialize(business, remote, fetched_at)
    @business = business
    @remote = remote
    @fetched_at = fetched_at
  end

  def apply!
    verify!
    Tenancy.with_business(@business) do
      @business.with_lock do
        row = @business.reload_subscription || @business.build_subscription
        return row if row.synced_at && row.synced_at > @fetched_at # a newer state is already applied

        if row.persisted? && row.stripe_subscription_id != @remote.id
          # An older subscription's late news never replaces a live one.
          return row if row.live? && !Subscription::LIVE_STATUSES.include?(@remote.status)

          # Two live subscriptions (two checkouts paid at once): keep the newer, and tell an
          # operator so the other can be cancelled and refunded in Stripe.
          if row.live? && Subscription::LIVE_STATUSES.include?(@remote.status)
            Observability.alert("A business has two live Stripe subscriptions", business_id: @business.id, kept: @remote.id,
                                                                                 replaced: row.stripe_subscription_id)
          end
        end
        before = row.attributes.slice(*%w[stripe_subscription_id status plan_id interval cancel_at_period_end])
        row.assign_attributes(attributes)
        # BIL-05: the grace period runs from the first failure of this subscription's renewal.
        row.past_due_since = row.past_due? ? (before["status"] == "past_due" && row.past_due_since) || Time.current : nil
        record_changes(before, row)
        row.save!
        Billing::PlanResolver.apply!(@business)
        row
      end
    end
  end

  private

  # Only a subscription of this business's own Stripe customer is mirrored; a mismatch is
  # reported and nothing changes.
  def verify!
    customer = @remote.customer.respond_to?(:id) ? @remote.customer.id : @remote.customer.to_s
    uid = @remote.metadata&.[]("business_uid")
    return if @business.stripe_customer_id.present? && customer == @business.stripe_customer_id && (uid.blank? || uid == @business.uid)

    raise Mismatch, "Stripe subscription #{@remote.id} doesn't belong to business #{@business.id}"
  end

  def attributes
    item = @remote.items.data.first
    plan, interval = Billing.plan_for_price(item&.price)
    {
      stripe_subscription_id: @remote.id, status: @remote.status, plan:, interval:, synced_at: @fetched_at,
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
