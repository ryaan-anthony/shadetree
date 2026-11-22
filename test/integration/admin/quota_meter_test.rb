require "test_helper"

# BIL-06: the quota meter at the foot of the sidebar: quotes sent this usage period of the plan's
# limit, the reset date, its states in words, who sees it, the Plan link, and one count per page.
class Admin::QuotaMeterTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15)
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    sign_in_as @owner
  end

  def sign_in_as(user, business: @business)
    sign_in user
    post switch_admin_business_path, params: { business: business.uid }
  end

  def sent(count, business: @business)
    as_business(business) do
      client = Client.create!(display_name: "Client #{SecureRandom.hex(2)}", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
      count.times { UsageEvent.record!("quote_sent", Quote.start(client:)) }
    end
  end

  def limits(quotes) = @business.update!(plan_overrides: { "limits" => { "quotes_sent" => quotes } })

  test "always shown: the label, a bar, \"3 of 5\" and the reset date, read as text in a region" do
    get admin_root_path
    assert_select "#quota-meter .quota-label", "Free quotes this month"
    assert_select "#quota-count", "0 of 5"
    sent(3)
    get admin_quotes_path
    assert_select "section#quota-meter[aria-label='Quote usage'] .quota-label:not([aria-hidden])", "Free quotes this month"
    assert_select "#quota-count", "3 of 5"
    assert_select "#quota-meter .quota-text", text: "3 of 5 used"
    assert_select "#quota-resets", "Resets Dec 1"
    assert_select "#quota-meter .quota-state", 0, "normal needs no word"
    assert_select "#quota-meter .quota-bar.quota-ok[aria-hidden=true]", 1, "the bar is decoration"
    assert_select "#quota-meter [role=meter]", 0
    assert_select "#quota-plan-link[href=?]", admin_plan_path
  end

  test "approaching, then Limit reached at the limit (no grace send), and over it after a downgrade" do
    sent(4)
    get admin_root_path
    assert_select "#quota-meter .quota-bar.quota-approaching"
    assert_select "#quota-meter .quota-text", /4 of 5 used\s*·\s*Nearly used, 1 left/
    sent(1)
    get admin_root_path
    assert_select "#quota-meter .quota-bar.quota-blocked"
    assert_select "#quota-meter .quota-text", /5 of 5 used\s*·\s*Limit reached/

    sent(1) # sent on a bigger plan, then downgraded mid-period
    get admin_root_path
    assert_select "#quota-meter .quota-text", /6 of 5 used\s*·\s*Limit reached/, "the real count"
    assert_match(/width: 100%/, css_select("style").map(&:text).join)
  end

  test "unlimited plans show the count without a bar; a plan without sending says so" do
    sent(42)
    limits(nil)
    get admin_root_path
    assert_select "#quota-unlimited", "42 quotes sent this month · no limit"
    assert_select "#quota-meter .quota-bar", 0
    limits(0)
    get admin_root_path
    assert_select "#quota-not-included", "Sending quotes isn't included on Free."
    assert_select "#quota-plan-link[href=?]", admin_plan_path
  end

  test "a trial shows the trial plan's limit, marked, and when the trial ends before the reset" do
    @business.update!(plan: plans(:starter), billing_status: "trialing", trial_plan: plans(:starter), trial_ends_at: Time.utc(2026, 11, 28, 17))
    get admin_root_path
    assert_select "#quota-meter .quota-label", "Starter quotes this month (trial)"
    assert_select "#quota-count", "0 of 30"
    assert_select "#quota-resets", "Resets Dec 1 · Trial ends Nov 28"
    @business.update!(trial_ends_at: Time.utc(2026, 12, 5))
    get admin_root_path
    assert_select "#quota-resets", "Resets Dec 1"
    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => nil } })
    get admin_root_path
    assert_select "#quota-unlimited", "0 quotes sent this month (trial) · no limit", "an unlimited trial says so too"
  end

  test "a limit of one: nearly used from the start, with one left; then reached" do
    limits(1)
    get admin_root_path
    assert_select "#quota-meter .quota-text", /0 of 1 used\s*·\s*Nearly used, 1 left/
    sent(1)
    get admin_root_path
    assert_select "#quota-meter .quota-text", /1 of 1 used\s*·\s*Limit reached/
  end

  test "past due shows the plan it's on now; a suspended business's refusal page has no meter" do
    sent(2)
    @business.update!(plan: plans(:starter), billing_status: "past_due", billing_cycle_anchor: Time.utc(2026, 10, 10, 15))
    get admin_root_path
    assert_select "#quota-meter .quota-label", "Starter quotes this billing period"
    assert_select "#quota-count", "2 of 30"

    @business.update!(suspended_at: Time.current)
    get admin_root_path
    assert_response :forbidden
    assert_select "#quota-meter", 0
    assert_select "#quota-plan-link", 0
  end

  test "after a plan change mid-period: the new plan's label and limit, with the period then in force, as Settings → Plan shows" do
    sent(7)
    @business.update!(plan: plans(:starter), billing_status: "active", billing_cycle_anchor: Time.utc(2026, 10, 10, 15))
    get admin_plan_path
    assert_select "#quota-meter .quota-label", "Starter quotes this billing period"
    assert_select "#quota-resets", "Resets Dec 10"
    assert_select "#usage-resets", /Dec 10/
    as_business(@business) { assert_equal 7, UsagePeriod.for(@business).used }
    assert_select "#quota-count", "7 of 30"
    assert_select "#limit-quotes_sent dd", "7 of 30"
  end

  test "who sees it: office access or business settings; the Plan link only with business settings" do
    get admin_root_path
    assert_select "#quota-meter"
    admin = member_with_role(:admin)
    sign_in_as admin
    get admin_root_path
    assert_select "#quota-plan-link"

    tech = member_with_role(:technician)
    sign_in_as tech
    get admin_my_day_path
    assert_response :success
    assert_select "#quota-meter", 0

    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    office = member_with_role(:technician)
    settings = member_with_role(:technician)
    as_business(@business) do
      @business.business_users.find_by!(user: office).update!(role: "custom", role_id: Role.create!(name: "Office", permissions: %w[office]).id)
      @business.business_users.find_by!(user: settings).update!(role: "custom", role_id: Role.create!(name: "Settings", permissions: %w[business_settings]).id)
    end
    sign_in_as office
    get admin_quotes_path
    assert_select "#quota-meter"
    assert_select "#quota-plan-link", 0, "plain text without business settings"
    sign_in_as settings
    get admin_catalog_items_path
    assert_select "#quota-plan-link[href=?]", admin_plan_path
  end

  test "operators viewing as a member see it by that member's rules" do
    sent(2, business: businesses(:two))
    sign_in_operator
    post ops_business_impersonation_path(businesses(:two)), params: { member: business_users(:two).uid, reason: "Ticket: how many quotes are left" }
    get admin_root_path
    assert_select "#quota-count", "2 of 5"
    assert_select "#quota-plan-link"
  end

  test "another business's usage is never shown" do
    sent(4, business: businesses(:two))
    sent(1)
    get admin_root_path
    assert_select "#quota-count", "1 of 5"
  end

  test "one count of quotes sent per page, shared with Home's allowance line and the notices" do
    sent(4)
    [ admin_root_path, admin_quotes_path, admin_plan_path ].each do |path|
      counts = []
      callback = ->(*, payload) { counts << payload[:sql] if payload[:sql].match?(/FROM "usage_events"/) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path }
      assert_response :success
      assert_equal 1, counts.size, "#{path}: #{counts}"
    end
  end
end
