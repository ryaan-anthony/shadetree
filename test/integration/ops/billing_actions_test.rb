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

    post ops_business_billing_comp_path(@business), params: { plan: "", reason: "Beta over" }
    assert_equal [ plans(:free), "free" ], @business.reload.values_at(:plan, :billing_status)

    post ops_business_billing_comp_path(@business), params: { plan: "business", ends_on: "2020-01-01", reason: "x" }
    assert_match "in the future", flash[:alert]
    post ops_business_billing_comp_path(@business), params: { plan: "business", reason: " " }
    assert_equal "Give a reason.", flash[:alert]
    assert_equal plans(:free), @business.reload.plan
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
