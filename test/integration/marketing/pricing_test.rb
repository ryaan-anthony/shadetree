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
    plan.update!(features: plan.features.merge("automations" => true, "remove_powered_by" => true))
    get pricing_path
    assert_select "#plan-#{plan.key} li", text: /Automations\s*Coming soon/
    assert_select "#plan-starter li", text: /No “Powered by Shadetree”/ do |items|
      items.each { assert_no_match(/Coming soon/, _1.text, "a built feature is just listed") }
    end
  end

  test "yearly prices and their saving come from the plan" do
    assert_equal "2 months free", plan_annual_saving(Plan.new(monthly_price_cents: 1_900, annual_price_cents: 19_000, currency: "USD"))
    assert_nil plan_annual_saving(Plan.new(monthly_price_cents: 1_900, annual_price_cents: 22_800, currency: "USD"))
    assert_equal "$15.83", plan_annual_monthly(Plan.new(annual_price_cents: 19_000, currency: "USD"))
    get pricing_path
    assert_select "fieldset legend", "Billing"
    assert_select "input[type=radio][name=billing]", 2
  end

  test "the FAQ answers limits, what happens at the limit, people, cancelling and data export" do
    get pricing_path
    assert_select "#faq ~ div details summary", text: /What counts as a quote/
    assert_select "#faq ~ div details summary", text: /reach my limit/
    assert_select "#faq ~ div details summary", text: /per person/
    assert_select "#faq ~ div details summary", text: /cancel/
    assert_select "#faq ~ div details summary", text: /take my data/
    assert_no_match(/trial|most popular|card payments|pay online/i, response.body)
  end
end
