require "test_helper"

# OPS-04 with BIL-05: comping a plan (with an end date), changing a trial and applying a Stripe
# coupon, each audited and in the billing history; and Trial / Past due in the directory.
class Ops::BillingActionsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:two)
    sign_in_operator
  end

  def history = as_business(@business) { BillingEvent.recent.map { [ _1.kind, _1.summary ] } }

  test "comping a plan until a date applies it at once; clearing it returns to Free" do
    ends_on = 30.days.from_now.to_date
    post ops_business_billing_comp_path(@business), params: { plan: "business", ends_on: ends_on.iso8601, reason: "Beta user" }
    assert_redirected_to ops_business_path(@business, anchor: "billing-actions")
    @business.reload
    assert_equal [ plans(:business), "comped", @business.time_zone.local(ends_on.year, ends_on.month, ends_on.day).end_of_day.to_i ],
                 [ @business.plan, @business.billing_status, @business.comp_ends_at.to_i ]
    entry = AuditEntry.find_by!(action: "business.plan_comped")
    assert_equal [ "Beta user", "business" ], [ entry.reason, entry.data["to"] ]
    assert_equal [ "comped", "Business, until #{ends_on.iso8601}, Beta user" ], history.find { _1.first == "comped" }
    get ops_business_path(@business)
    assert_select "#comp", /Business, until/
    assert_select "#comp time[datetime]", 1
    assert_no_match "&lt;time", response.body, "the end date is a date, not escaped markup"

    post ops_business_billing_comp_path(@business), params: { plan: "", reason: "Beta over" }
    assert_equal "Choose a paid plan to comp.", flash[:alert]
    post ops_business_billing_comp_path(@business), params: { plan: "platinum", reason: "Beta over" }
    assert_equal "Choose a paid plan to comp.", flash[:alert]
    assert_equal plans(:business), @business.reload.plan, "only an explicit remove clears a comp"
    post ops_business_billing_comp_path(@business), params: { remove_comp: "1", reason: "Beta over" }
    assert_equal [ plans(:free), "free", nil ], @business.reload.values_at(:plan, :billing_status, :comp_plan)

    post ops_business_billing_comp_path(@business), params: { plan: "business", ends_on: "2020-01-01", reason: "x" }
    assert_match "in the future", flash[:alert]
    post ops_business_billing_comp_path(@business), params: { plan: "business", reason: " " }
    assert_equal "Give a reason.", flash[:alert]
    assert_equal plans(:free), @business.reload.plan
  end

  test "a comp is refused while the business has a live subscription, mirrored or only in Stripe" do
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter))
    post ops_business_billing_comp_path(@business), params: { plan: "business", reason: "Beta" }
    assert_match "live Stripe subscription", flash[:alert]
    assert_match "100%-off coupon", flash[:alert]
    assert_nil @business.reload.comp_plan

    Billing::SubscriptionSync.refresh!(@business, id)
    get ops_business_path(@business)
    assert_select "#comp-refused", /100%-off coupon/
    assert_select "form[action='#{ops_business_billing_comp_path(@business)}'] select", 0
    post ops_business_billing_comp_path(@business), params: { plan: "business", reason: "Beta" }
    assert_equal plans(:starter), @business.reload.plan
  end

  test "extending a trial (or giving one) moves its end and its reminders" do
    @business.update_columns(trial_plan_id: plans(:starter).id, trial_ends_at: 1.day.ago, trial_reminded_days: 1)
    post ops_business_billing_trial_path(@business), params: { ends_on: 10.days.from_now.to_date.iso8601, reason: "Wants another week" }
    @business.reload
    assert_equal [ plans(:starter), "trialing", nil ], [ @business.plan, @business.billing_status, @business.trial_reminded_days ]
    assert AuditEntry.exists?(action: "business.trial_changed", business_id: @business.id)
    get ops_businesses_path(status: "trial")
    assert_select "#businesses > li", 1
    assert_select "#business-#{@business.uid}", /Trial/

    post ops_business_billing_trial_path(@business), params: { ends_on: "", reason: "x" }
    assert_match "in the future", flash[:alert]
  end

  test "ending a trial moves the business back to Free now, tells its Owners, and is audited" do
    @business.update_columns(trial_plan_id: plans(:starter).id, trial_ends_at: 10.days.from_now)
    Billing::PlanResolver.apply!(@business)
    assert_equal [ plans(:starter), "trialing" ], [ @business.reload.plan, @business.billing_status ]

    get ops_business_path(@business)
    assert_select "form#end-trial input[type=submit][value='End trial']"
    assert_select "#trial", /Starter, ends/
    assert_select "#trial time[datetime]", 1
    assert_no_match "&lt;time", response.body, "the end date is a date, not escaped markup"

    post ops_business_billing_end_trial_path(@business), params: { reason: "" }
    assert_equal "Give a reason.", flash[:alert]
    assert_equal plans(:starter), @business.reload.plan, "a reason is needed"

    assert_enqueued_emails 1 do
      post ops_business_billing_end_trial_path(@business), params: { reason: "Asked to cancel before it ends" }
    end
    assert_redirected_to ops_business_path(@business, anchor: "billing-actions")
    assert_match "back on Free", flash[:notice]
    @business.reload
    assert_equal [ plans(:free), "free", true ], [ @business.plan, @business.billing_status, @business.trial_ends_at <= Time.current ]
    entry = AuditEntry.find_by!(action: "business.trial_ended", business_id: @business.id)
    assert_equal "Asked to cancel before it ends", entry.reason
    assert_includes history, [ "trial_ended_early", "Starter, was due #{10.days.from_now.to_date.iso8601}, Asked to cancel before it ends" ]
    assert_includes history.map(&:first), "plan_changed"

    get ops_business_path(@business)
    assert_select "#trial", /ended/
    assert_select "form#end-trial", 0
    post ops_business_billing_end_trial_path(@business), params: { reason: "Again" }
    assert_equal "There's no trial running to end.", flash[:alert]
  end

  test "ending a trial leaves a comp or subscription's plan alone" do
    @business.update_columns(trial_plan_id: plans(:starter).id, trial_ends_at: 10.days.from_now, comp_plan_id: plans(:business).id)
    Billing::PlanResolver.apply!(@business)
    post ops_business_billing_end_trial_path(@business), params: { reason: "Trial no longer needed" }
    assert_match "a comp keeps", flash[:notice]
    assert_equal [ plans(:business), "comped" ], [ @business.reload.plan, @business.billing_status ]
  end

  test "ending a trial is refused while there's a live subscription, and the button isn't offered" do
    @business.update_columns(trial_plan_id: plans(:starter).id, trial_ends_at: 10.days.from_now)
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter))
    Billing::SubscriptionSync.refresh!(@business, id)
    get ops_business_path(@business)
    assert_select "form#end-trial", 0

    post ops_business_billing_end_trial_path(@business), params: { reason: "Stop it" }
    assert_match "live Stripe subscription", flash[:alert]
    assert @business.reload.trial_ends_at.future?
    assert_not AuditEntry.exists?(action: "business.trial_ended")
  end

  test "a coupon is applied to the Stripe subscription; without one it's refused, and Stripe's refusal is shown" do
    post ops_business_billing_coupon_path(@business), params: { coupon: "BETA50", reason: "Beta" }
    assert_match "no subscription", flash[:alert]

    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter))
    Billing::SubscriptionSync.refresh!(@business, id)
    post ops_business_billing_coupon_path(@business), params: { coupon: "BETA50", reason: "Beta" }
    assert_equal [ { coupon: "BETA50" } ], stripe.subscriptions[id][:discounts]
    post ops_business_billing_coupon_path(@business), params: { coupon: "promo_123", reason: "Beta" }
    assert_equal [ { promotion_code: "promo_123" } ], stripe.subscriptions[id][:discounts]
    assert_equal 2, AuditEntry.where(action: "business.coupon_applied").count
    assert_equal [ "coupon_applied", "promo_123, Beta" ], history.first

    stripe.fail_with = Stripe::InvalidRequestError.new("No such coupon: 'NOPE'", "coupon")
    post ops_business_billing_coupon_path(@business), params: { coupon: "NOPE", reason: "Beta" }
    assert_match "Stripe refused it: No such coupon", flash[:alert]
    post ops_business_billing_coupon_path(@business), params: { coupon: "bad id!", reason: "Beta" }
    assert_match "Enter a Stripe coupon", flash[:alert]
  end

  test "past due businesses are listed as such" do
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter), status: "past_due")
    Billing::SubscriptionSync.refresh!(@business, id)
    get ops_businesses_path(status: "past_due")
    assert_select "#businesses > li", 1
    assert_select "#business-#{@business.uid}", /Past due/
    get ops_businesses_path(status: "trial")
    assert_select "#businesses > li", 0
    get ops_businesses_path(status: "active")
    assert_select "#business-#{@business.uid}", 0, "Active excludes Trial and Past due"
  end

  test "billing actions need a recent code" do
    travel 10.minutes do
      sign_in users(:one)
      post ops_business_billing_comp_path(@business), params: { plan: "business", reason: "Beta" }
    end
    assert_redirected_to new_ops_two_factor_verification_path(recent: 1)
    assert_equal plans(:free), @business.reload.plan
  end
end
