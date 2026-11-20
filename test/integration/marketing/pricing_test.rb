require "test_helper"

# MKT-01: the pricing page renders plans, prices, limits and features from the plan data
# (BIL-01), so it can't drift from what the app enforces, and answers the usual questions.
class MarketingPricingTest < ActionDispatch::IntegrationTest
  include MarketingHelper
  include ActionView::Helpers::NumberHelper

  test "every listed plan with its prices, quota, team size and features, in order" do
    get pricing_path
    assert_response :success
    assert_select "title", /Pricing/
    plans = Plan.listed.to_a
    assert_equal plans.map(&:name), css_select("[aria-label=Plans] > ul > li h2").map { _1.text.strip }
    plans.each do |plan|
      assert_select "#plan-#{plan.key}" do
        assert_select "*", text: /#{Regexp.escape(plan_quota(plan))}/
        assert_select "li", text: plan_team(plan)
        unless plan.free?
          assert_select "span", text: plan_price(plan.monthly_price)
          assert_select "span", text: "#{plan_price(plan.annual_price)} billed yearly"
        end
        assert_select "a[href=?]", new_user_registration_path, text: "Start free"
      end
    end
  end

  test "editing a plan changes the page; a hidden plan isn't shown" do
    plan = Plan.listed.where.not(monthly_price_cents: 0).first
    plan.update!(monthly_price_cents: 2_500, limits: plan.limits.merge("quotes_sent" => 42))
    get pricing_path
    assert_select "#plan-#{plan.key} span", text: "$25"
    assert_select "#plan-#{plan.key}", text: /42 quotes a month/
    plan.update!(public: false)
    get pricing_path
    assert_select "#plan-#{plan.key}", false
  end

  test "features not built yet are marked coming soon, never promised" do
    plan = Plan.listed.last
    plan.update!(features: plan.features.merge("sms" => true, "remove_powered_by" => true, "locations" => true, "custom_roles" => true))
    get pricing_path
    assert_select "#plan-#{plan.key} li", text: /Text messages\s*Coming soon/
    [ /More than one location/, /Custom roles/ ].each do |feature| # CAT-07 and ACC-07 shipped
      assert_select "#plan-#{plan.key} li", text: feature do |items|
        items.each { assert_no_match(/Coming soon/, _1.text) }
      end
    end
    assert_select "#plan-starter li", text: /No “Powered by Shadetree”/ do |items|
      items.each { assert_no_match(/Coming soon/, _1.text, "a built feature is just listed") }
    end
  end

  test "yearly prices and their saving come from the plan" do
    assert_equal "2 months free", plan_annual_saving(Plan.new(monthly_price_cents: 1_900, annual_price_cents: 19_000, currency: "USD"))
    assert_nil plan_annual_saving(Plan.new(monthly_price_cents: 1_900, annual_price_cents: 22_800, currency: "USD"))
    assert_equal "$15.83", plan_annual_monthly(Plan.new(annual_price_cents: 19_000, currency: "USD"))
    assert_nil plan_annual_saving(Plan.new(monthly_price_cents: 1_900, annual_price_cents: 0, currency: "USD")), "no yearly price, no yearly option"
    assert_nil plan_annual_saving(Plan.new(monthly_price_cents: 1_900, annual_price_cents: 30_000, currency: "USD")), "dearer yearly saves nothing"
    assert_equal "€19", plan_price(Money.new(1_900, "EUR"))
    get pricing_path
    assert_select "fieldset legend", "Billing"
    assert_select "input[type=radio][name=billing]", 2
  end

  test "a plan without a yearly price shows its monthly price either way, and mixed savings are shown per plan" do
    Plan.find_by!(key: "starter").update!(annual_price_cents: 0)
    get pricing_path
    assert_select "#plan-starter span", text: "$19"
    assert_select "#plan-starter", text: /billed monthly/
    assert_no_match(/\$0 billed yearly|12 months free/, response.body)
    Plan.find_by!(key: "starter").update!(annual_price_cents: 20_900) # one month free; Business saves two
    get pricing_path
    assert_includes css_select("fieldset label").map { _1.text.squish }, "Yearly"
    assert_select "#plan-business", text: /2 months free/
  end

  test "the FAQ answers limits, what happens at the limit, people, cancelling and data export" do
    get pricing_path
    assert_select "#faq ~ div details summary", text: /What counts as a quote/
    assert_select "#faq ~ div details summary", text: /reach my limit/
    assert_select "#faq ~ div details summary", text: /per person/
    assert_select "#faq ~ div details summary", text: /cancel/
    assert_select "#faq ~ div details summary", text: /take my data/
    assert_no_match(/most popular|card payments|pay online|read-only|move to a paid plan from Settings/i, response.body)
    assert_select "a[href=?]", contact_path, text: "Ask us"
  end

  test "says a new business starts with the trial (BIL-05), or on Free when there's none" do
    settings = Rails.configuration.x.billing
    settings.trial_days, settings.trial_plan = 14, "business"
    get pricing_path
    assert_match "A new business starts with a 14-day Business trial, no card needed", response.body
    settings.trial_days = 0
    get pricing_path
    assert_match "Every account starts on Free.", response.body
  ensure
    settings.trial_days = 0
  end

  test "says where Owners choose a paid plan (BIL-04), and what cancelling means" do
    get pricing_path
    assert_match "Owners choose a paid plan in Settings → Plan", response.body
    assert_no_match(/coming soon; until then/, response.body)
    assert_select "#faq ~ div details p", text: /runs to the end of what you’ve paid for, then you’re on Free/
  end
end
