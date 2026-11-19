require "test_helper"

# BIL-01: Settings → Plan, and the gates wired to plans: the team size on invitations, and the
# number of free businesses one person may own.
class Admin::PlanSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "the plan page shows the plan, what's used and included, and the other plans; only for settings people" do
    get admin_plan_path
    assert_response :success
    assert_select "#current-plan", /You're on Free/
    assert_select "#limit-team_members", /1 of 2/
    assert_select "#limit-quotes_sent", /0 of 5/
    assert_select "#compare-plans th", /Starter.*\$19\.00\/month/m
    assert_select "#compare-plans th", /Free \(yours\)/
    assert_select "#compare-plans td", /Unlimited/

    plans(:starter).update!(public: false)
    @business.update!(plan: plans(:starter))
    get admin_plan_path
    assert_select "#compare-plans th", /Starter \(yours\)/, "a hidden plan the business is on still shows"
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_plan_path }
  end

  test "invitations stop at the plan's team size, counting pending ones" do
    post admin_invitations_path, params: { invitation: { email: "first@example.com", role: "technician" } }
    assert_match "Invitation sent", flash[:notice]
    post admin_invitations_path, params: { invitation: { email: "second@example.com", role: "technician" } }
    assert_match "Your Free plan includes 2 team members", flash[:alert]
    @business.update!(plan_overrides: { "limits" => { "team_members" => 5 } })
    post admin_invitations_path, params: { invitation: { email: "second@example.com", role: "technician" } }
    assert_match "Invitation sent", flash[:notice]
  end

  test "one person may own three businesses on the free plan" do
    2.times { |i| Business.create!(owner: @owner, name: "Shop #{i}", industry: "landscaping", timezone: "America/New_York") }
    post admin_business_path, params: { business: { name: "Fourth", industry: "landscaping", timezone: "America/New_York" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /already own 3 businesses on the free plan/
    @owner.owned_businesses.where.not(id: @business.id).first.update!(plan: plans(:starter))
    post admin_business_path, params: { business: { name: "Fourth", industry: "landscaping", timezone: "America/New_York" } }
    assert_redirected_to admin_root_path
  end
end
