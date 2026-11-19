require "test_helper"

# OPS-04: editing plans, and comping one business's limits or features, each audited.
class Ops::PlansTest < ActionDispatch::IntegrationTest
  setup { @business = businesses(:one) }

  test "operators edit a plan's name, prices, limits and features" do
    plan = plans(:starter)
    sign_in users(:two)
    get admin_root_path
    get ops_plans_path
    assert_response :not_found
    sign_out :user

    sign_in_operator
    get ops_plans_path
    assert_select "#plan-starter", /Starter/
    get edit_ops_plan_path(plan)
    assert_response :success
    patch ops_plan_path(plan), params: { plan: { name: "Starter+", monthly_price: "35.50", annual_price: "350", public: "1", position: "1",
                                                 limits: { "quotes_sent" => "40", "team_members" => "", "active_automations" => "3" },
                                                 features: { "automations" => "1", "sms" => "0" } } }
    assert_redirected_to ops_plans_path
    plan.reload
    assert_equal [ "Starter+", 3550, 35_000 ], [ plan.name, plan.monthly_price_cents, plan.annual_price_cents ]
    assert_equal({ "quotes_sent" => 40, "active_automations" => 3 }, plan.limits)
    assert_equal({ "automations" => true }, plan.features)
    entry = AuditEntry.find_by!(action: "plan.updated")
    assert_equal "starter", entry.data["plan"]
    assert_includes entry.data["changed"], "limits"

    patch ops_plan_path(plan), params: { plan: { name: "", monthly_price: "lots" } }
    assert_response :unprocessable_content
    assert_equal "Starter+", plan.reload.name
  end

  test "operators comp one business's limits and features with a reason; entitlements follow" do
    sign_in_operator
    get edit_ops_business_plan_overrides_path(@business)
    assert_response :success
    params = { limits: { "quotes_sent" => { mode: "custom", value: "500" }, "team_members" => { mode: "unlimited" }, "active_automations" => { mode: "" } },
               features: { "automations" => "on", "sms" => "", "remove_powered_by" => "off" } }
    patch ops_business_plan_overrides_path(@business), params: params
    assert_match "Give a reason", flash[:alert]
    patch ops_business_plan_overrides_path(@business), params: params.merge(reason: "Beta customer")
    assert_redirected_to ops_business_path(@business, anchor: "plan")
    @business.reload
    assert_equal({ "limits" => { "quotes_sent" => 500, "team_members" => nil }, "features" => { "automations" => true, "remove_powered_by" => false } }, @business.plan_overrides)
    assert_equal [ 500, nil, true ], [ @business.entitlements.limit(:quotes_sent), @business.entitlements.limit(:team_members), @business.entitlements.feature?(:automations) ]
    entry = AuditEntry.find_by!(action: "business.plan_overrides_changed")
    assert_equal [ @business, "Beta customer", {} ], [ entry.business, entry.reason, entry.data["from"] ]
    get ops_business_path(@business)
    assert_select "#overrides", /Quotes sent a month 500/

    patch ops_business_plan_overrides_path(@business), params: { limits: { "quotes_sent" => { mode: "custom", value: "-3" } }, reason: "x" }
    assert_response :unprocessable_content
    patch ops_business_plan_overrides_path(@business), params: { reason: "Back to normal" }
    assert_equal({}, @business.reload.plan_overrides)
  end
end
