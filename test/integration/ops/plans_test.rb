require "test_helper"

# OPS-04: editing plans, and comping one business's limits or features, each audited.
class Ops::PlansTest < ActionDispatch::IntegrationTest
  setup { @business = businesses(:one) }

  test "businesses on a trial are listed apart from the plan's paying businesses" do
    pro = plans(:starter)
    Business.update_all(plan_id: plans(:free).id, billing_status: "free")
    paying = Business.limit(1).first
    paying.update_columns(plan_id: pro.id, billing_status: "active")
    Business.where.not(id: paying.id).update_all(plan_id: pro.id, billing_status: "trialing")
    trials = Business.where(billing_status: "trialing").count

    sign_in_operator
    get ops_plans_path
    assert_select "#plan-starter", /· 1 business/
    assert_select "#trial-plan-starter", /Trial\s*· Starter/
    assert_select "#trial-plan-starter", /#{trials} business/
    assert_select "#trial-plan-free", false
  end

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
    assert_equal({ "from" => "Starter", "to" => "Starter+" }, entry.data["changes"]["name"])
    assert_equal({ "quotes_sent" => 40, "active_automations" => 3 }, entry.data["changes"]["limits"]["to"])

    [ "3O", "-1" ].each do |typo|
      patch ops_plan_path(plan), params: { plan: { name: "Starter+", limits: { "quotes_sent" => typo, "team_members" => "", "active_automations" => "3" } } }
      assert_response :unprocessable_content
      assert_equal 40, plan.reload.limits["quotes_sent"], "#{typo} isn't taken as unlimited"
    end

    patch ops_plan_path(plan), params: { plan: { name: "", monthly_price: "lots" } }
    assert_response :unprocessable_content
    assert_equal "Starter+", plan.reload.name

    # PAY-04: the platform fee on online payments, 0 until one is decided, at most 10%.
    assert_equal 0, plan.platform_fee_bps
    patch ops_plan_path(plan), params: { plan: { platform_fee_bps: "50" } }
    assert_equal 50, plan.reload.platform_fee_bps
    patch ops_plan_path(plan), params: { plan: { platform_fee_bps: "5000" } }
    assert_response :unprocessable_content
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
