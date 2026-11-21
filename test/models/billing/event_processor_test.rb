require "test_helper"

# BIL-04: Stripe events update the business's subscription, plan and billing history, the same
# whatever the order or number of times they arrive.
class Billing::EventProcessorTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @customer = with_stripe_customer(@business)
  end

  def event(type, object_id, customer: @customer)
    StripeEvent.create!(stripe_event_id: "evt_#{SecureRandom.hex(6)}", event_type: type, stripe_object_id: object_id, customer_id: customer,
                        stripe_created_at: Time.current, created_at: Time.current)
  end

  def process(type, object_id, **) = StripeEventJob.perform_now(event(type, object_id, **).id)

  def history = Tenancy.with_business(@business) { BillingEvent.recent.map { [ _1.kind, _1.summary ] } }
  def subscription = Tenancy.with_business(@business) { @business.reload.subscription }

  test "a new subscription puts the business on its plan, from its billing cycle" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter), interval: "yearly", period_start: 3.days.ago)

    process("customer.subscription.created", id)

    @business.reload
    assert_equal plans(:starter), @business.plan
    assert_equal subscription.billing_cycle_anchor, @business.billing_cycle_anchor
    assert_equal [ "active", "yearly", plans(:starter) ], subscription.values_at(:status, :interval, :plan)
    assert_equal [ [ "plan_changed", "Free → Starter" ], [ "subscribed", "Starter, yearly" ] ], history
    assert StripeEvent.last.processed_at
  end

  test "checkout completing applies the session's subscription" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:business))
    session = stripe.create_checkout_session(customer: @customer, mode: "subscription")
    stripe.checkout_sessions[session.id][:subscription] = id

    process("checkout.session.completed", session.id)

    assert_equal plans(:business), @business.reload.plan
  end

  test "duplicates and out-of-order events end in Stripe's current state" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    created = event("customer.subscription.created", id)
    stripe.subscriptions[id].merge!(status: "canceled", ended_at: Time.current.to_i)
    deleted = event("customer.subscription.deleted", id)

    StripeEventJob.perform_now(deleted.id)
    StripeEventJob.perform_now(created.id) # arrives late: Stripe now says canceled
    StripeEventJob.perform_now(deleted.id) # and again

    assert_equal plans(:free), @business.reload.plan
    assert_equal "canceled", subscription.status
    assert_empty history.select { _1.first == "subscribed" }
  end

  test "switching plan or interval, scheduling and withdrawing a cancellation, and the end are recorded" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    process("customer.subscription.created", id)
    sub = stripe.subscriptions[id]
    sub[:items][:data][0][:price].merge!(product: "shadetree_business", recurring: { interval: "year" })
    process("customer.subscription.updated", id)
    sub[:cancel_at_period_end] = true
    process("customer.subscription.updated", id)
    sub[:cancel_at_period_end] = false
    process("customer.subscription.updated", id)
    sub.merge!(status: "canceled", ended_at: Time.current.to_i)
    process("customer.subscription.deleted", id)

    assert_equal %w[plan_changed ended cancel_withdrawn cancel_scheduled plan_changed switched plan_changed subscribed], history.map(&:first)
    assert_equal [ "switched", "Business, yearly" ], history[5]
    assert_equal plans(:free), @business.reload.plan
  end

  test "a failing renewal keeps the plan while Stripe retries" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    process("customer.subscription.created", id)
    stripe.subscriptions[id][:status] = "past_due"
    invoice = stripe.add_invoice(subscription: id, status: "open", amount: 1900, attempt_count: 1)

    process("invoice.payment_failed", invoice)
    process("invoice.payment_failed", invoice)

    assert_equal plans(:starter), @business.reload.plan
    assert_equal [ [ "past_due", nil ], [ "payment_failed", "$19.00 · invoice SHADE-#{invoice}" ] ], history.first(2)
    assert_equal 1, history.count { _1.first == "payment_failed" }
  end

  test "a paid invoice is recorded once; a zero one isn't" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    paid = stripe.add_invoice(subscription: id, amount: 1900)
    free = stripe.add_invoice(subscription: id, amount: 0)

    2.times { process("invoice.paid", paid) }
    process("invoice.paid", free)

    assert_equal 1, history.count { _1 == [ "payment_succeeded", "$19.00 · invoice SHADE-#{paid}" ] }
    assert_equal 1, history.count { _1.first == "payment_succeeded" }
  end

  test "an old subscription's late news doesn't replace a live one" do
    old = stripe.add_subscription(customer: @customer, plan: plans(:starter), status: "canceled")
    current = stripe.add_subscription(customer: @customer, plan: plans(:business))
    process("customer.subscription.created", current)

    process("customer.subscription.deleted", old)

    assert_equal current, subscription.stripe_subscription_id
    assert_equal plans(:business), @business.reload.plan
  end

  test "a subscription of another customer or business is reported and never mirrored" do
    reports = []
    subscriber = Class.new { define_method(:report) { |error, **| reports << error.class } }.new
    Rails.error.subscribe(subscriber)
    foreign = stripe.add_subscription(customer: "cus_someone_else", plan: plans(:business))
    process("customer.subscription.updated", foreign) # the event claims our customer
    other_uid = stripe.add_subscription(customer: @customer, plan: plans(:business), metadata: { business_uid: businesses(:two).uid })
    process("customer.subscription.created", other_uid)
    session = stripe.create_checkout_session(customer: @customer, client_reference_id: businesses(:two).uid)
    stripe.checkout_sessions[session.id][:subscription] = stripe.add_subscription(customer: @customer, plan: plans(:business))
    process("checkout.session.completed", session.id)

    assert_equal plans(:free), @business.reload.plan
    assert_nil subscription
    assert_equal [ Billing::SubscriptionSync::Mismatch ] * 3, reports
    assert StripeEvent.where(processed_at: nil).none?
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "when the mirrored subscription ends, another live one on the customer takes over instead of Free" do
    first = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    process("customer.subscription.created", first)
    second = stripe.add_subscription(customer: @customer, plan: plans(:business))
    stripe.subscriptions[first].merge!(status: "canceled", ended_at: Time.current.to_i)

    process("customer.subscription.deleted", first)

    assert_equal [ second, plans(:business) ], [ subscription.stripe_subscription_id, @business.reload.plan ]
  end

  test "a state fetched before the one already applied is ignored" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    stale = Billing.gateway.retrieve_subscription(id)
    stripe.subscriptions[id].merge!(status: "canceled", ended_at: Time.current.to_i)
    Billing::SubscriptionSync.refresh!(@business, id)

    Billing::SubscriptionSync.apply!(@business, stale, fetched_at: 1.minute.ago)

    assert_equal "canceled", subscription.status
  end

  test "the sweep backs off, gives up after #{StripeEvent::MAX_ATTEMPTS} attempts with one report, and processes inline" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    stuck = event("customer.subscription.created", id)
    stuck.update_columns(created_at: 1.hour.ago)
    stripe.fail_with = Stripe::APIConnectionError.new("down")
    alerts = []
    subscriber = Class.new { define_method(:report) { |error, **| alerts << error.message if error.is_a?(Observability::Alert) } }.new
    Rails.error.subscribe(subscriber)

    ProcessStripeEventsJob.perform_now
    assert_equal 1, stuck.reload.attempts
    ProcessStripeEventsJob.perform_now
    assert_equal 1, stuck.reload.attempts, "tried within its backoff"
    travel 1.day do
      (StripeEvent::MAX_ATTEMPTS + 2).times do
        ProcessStripeEventsJob.perform_now
        stuck.update_columns(last_attempted_at: 1.day.ago)
      end
    end

    assert_equal StripeEvent::MAX_ATTEMPTS, stuck.reload.attempts
    assert_equal [ "Gave up on a Stripe event after #{StripeEvent::MAX_ATTEMPTS} attempts" ], alerts
    assert_nil stuck.processed_at
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "a second live subscription replaces the first and alerts an operator" do
    first = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    second = stripe.add_subscription(customer: @customer, plan: plans(:business))
    process("customer.subscription.created", first)
    reports = []
    subscriber = Class.new { define_method(:report) { |error, **| reports << error.message } }.new
    Rails.error.subscribe(subscriber)

    process("customer.subscription.created", second)

    assert_equal second, subscription.stripe_subscription_id
    assert_includes reports, "A business has two live Stripe subscriptions"
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "events for a customer that isn't a business here are ignored" do
    id = stripe.add_subscription(customer: "cus_elsewhere", plan: plans(:starter))
    process("customer.subscription.created", id, customer: "cus_elsewhere")

    assert_equal plans(:free), @business.reload.plan
    assert_empty stripe.call_names
    assert StripeEvent.last.processed_at
  end

  test "Stripe being unreachable leaves the event for a retry, and the sweep picks it up" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    stuck = event("customer.subscription.created", id)
    stripe.fail_with = Stripe::APIConnectionError.new("down")
    assert_raises(Stripe::APIConnectionError) { Billing::EventProcessor.process!(stuck) }
    assert_nil stuck.reload.processed_at

    stripe.fail_with = nil
    stuck.update_columns(created_at: 11.minutes.ago)
    ProcessStripeEventsJob.perform_now

    assert stuck.reload.processed_at
    assert_equal plans(:starter), @business.reload.plan
  end
end
