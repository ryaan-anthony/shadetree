require "test_helper"

# BIL-05: trials, failed payments and their grace period, cancelling, reactivating and comps:
# each moves the plan at the right time, once, records it and tells the Owners when it's Free.
class Billing::LifecycleTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @customer = with_stripe_customer(@business)
  end

  def with_trial(days: 14, plan: "business")
    settings = Rails.configuration.x.billing
    before = [ settings.trial_days, settings.trial_plan ]
    settings.trial_days, settings.trial_plan = days, plan
    yield
  ensure
    settings.trial_days, settings.trial_plan = before
  end

  def new_business = Business.create!(owner: users(:one), name: "Fresh Cuts", industry: "landscaping", timezone: "America/New_York")
  def history(business = @business) = Tenancy.with_business(business) { BillingEvent.recent.map { [ _1.kind, _1.summary ] } }
  def sync(id) = Billing::SubscriptionSync.refresh!(@business, id)
  def checks_at(time) = travel_to(time) { BillingChecksJob.perform_now }

  test "a new business starts on the trial plan; reminders go out 3 days and 1 day before, once each; then it's on Free" do
    business = with_trial { new_business }
    assert_equal [ plans(:business), "trialing" ], [ business.plan, business.billing_status ]
    assert_in_delta 14.days.from_now, business.trial_ends_at, 5
    assert_equal [ "trial_started", "Business, until #{business.trial_ends_at.to_date.iso8601}" ], history(business).first
    assert_equal business.trial_ends_at - 3.days, business.billing_check_at

    assert_enqueued_email_with BillingMailer, :trial_ending, params: { business:, user: users(:one), days_left: 3 } do
      checks_at(business.trial_ends_at - 3.days + 1.minute)
    end
    assert_no_enqueued_emails { checks_at(business.trial_ends_at - 2.days) }
    assert_enqueued_emails(1) { checks_at(business.trial_ends_at - 1.day + 1.minute) }

    assert_enqueued_email_with BillingMailer, :moved_to_free, params: { business:, user: users(:one), from_plan: "Business", reason: "trial_ended" } do
      checks_at(business.trial_ends_at + 1.minute)
    end
    business.reload
    assert_equal [ plans(:free), "free", nil ], [ business.plan, business.billing_status, business.billing_check_at ]
    assert_equal [ "plan_changed", "Business → Free, the trial ended" ], history(business).first
    assert_no_enqueued_emails { checks_at(business.trial_ends_at + 2.hours) }
  end

  test "TRIAL_DAYS=0 means no trial; trialing businesses count toward the free-business cap" do
    assert_equal plans(:free), new_business.plan # with business one: two free
    with_trial do
      assert_equal "trialing", new_business.billing_status # the third
      assert_raises(ActiveRecord::RecordInvalid) { new_business }
    end
  end

  test "subscribing during a trial: the subscription's plan wins and no reminder or downgrade follows" do
    business = with_trial { new_business }
    customer = with_stripe_customer(business, id: "cus_fresh")
    Billing::SubscriptionSync.refresh!(business, stripe.add_subscription(customer:, plan: plans(:starter)))
    assert_equal [ plans(:starter), "active", nil ], business.reload.values_at(:plan, :billing_status, :billing_check_at)
    assert_no_enqueued_emails { Billing::TrialReminders.send_due!(business, at: business.trial_ends_at - 1.hour) }
  end

  test "a failed renewal keeps the plan through the grace period, then Free with an email; paying restores it at once" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    sync(id)
    failed_at = Time.current
    stripe.subscriptions[id][:status] = "past_due"
    sync(id)
    sync(id) # a later event doesn't restart the grace period
    @business.reload
    assert_equal [ plans(:starter), "past_due" ], [ @business.plan, @business.billing_status ]
    assert_in_delta failed_at + 7.days, @business.billing_check_at, 2

    checks_at(failed_at + 6.days)
    assert_equal plans(:starter), @business.reload.plan
    assert_enqueued_email_with BillingMailer, :moved_to_free, params: { business: @business, user: users(:one), from_plan: "Starter", reason: "unpaid" } do
      checks_at(failed_at + 7.days + 1.minute)
    end
    assert_equal [ plans(:free), "past_due" ], @business.reload.values_at(:plan, :billing_status)

    travel_to(failed_at + 9.days) do
      stripe.subscriptions[id][:status] = "active"
      sync(id)
    end
    assert_equal [ plans(:starter), "active" ], @business.reload.values_at(:plan, :billing_status)
    assert_nil Tenancy.with_business(@business) { @business.reload_subscription.past_due_since }
  end

  test "a cancelled subscription keeps the plan to the end of the paid period, then Free, even before Stripe's event" do
    id = stripe.add_subscription(customer: @customer, plan: plans(:starter), cancel_at_period_end: true)
    sync(id)
    period_end = Tenancy.with_business(@business) { @business.reload_subscription.current_period_end }
    assert_equal [ plans(:starter), period_end ], @business.reload.values_at(:plan, :billing_check_at)

    assert_enqueued_emails(1) { checks_at(period_end + 1.minute) }
    assert_equal plans(:free), @business.reload.plan
    travel_to(period_end + 2.minutes) do
      stripe.subscriptions[id].merge!(status: "canceled", ended_at: Time.current.to_i)
      assert_no_enqueued_emails { sync(id) }
    end
    assert_match "the subscription ended", history.find { _1.first == "plan_changed" }.last
  end

  test "an operator's comp wins until its end date, then the subscription or Free applies again" do
    @business.update!(comp_plan: plans(:business), comp_ends_at: 10.days.from_now)
    Billing::PlanResolver.apply!(@business)
    assert_equal [ plans(:business), "comped" ], @business.reload.values_at(:plan, :billing_status)
    assert_enqueued_emails(1) { checks_at(11.days.from_now) }
    assert_equal plans(:free), @business.reload.plan
    assert_match "the comped plan ended", history.first.last

    id = stripe.add_subscription(customer: @customer, plan: plans(:starter))
    sync(id)
    @business.update!(comp_plan: plans(:business), comp_ends_at: nil)
    Billing::PlanResolver.apply!(@business)
    assert_equal plans(:business), @business.reload.plan
    @business.update!(comp_plan: nil)
    assert_no_enqueued_emails { Billing::PlanResolver.apply!(@business) }
    assert_equal plans(:starter), @business.reload.plan
  end

  test "checks are idempotent and only touch businesses that are due" do
    @business.update_columns(trial_plan_id: plans(:starter).id, trial_ends_at: 1.hour.ago, billing_check_at: 1.hour.ago, plan_id: plans(:starter).id)
    businesses(:two).update_columns(trial_plan_id: plans(:starter).id, trial_ends_at: 1.hour.ago, plan_id: plans(:starter).id)
    assert_enqueued_emails(1) { 2.times { BillingChecksJob.perform_now } }
    assert_equal plans(:free), @business.reload.plan
    assert_equal plans(:starter), businesses(:two).reload.plan, "not due: no check scheduled"
  end
end
