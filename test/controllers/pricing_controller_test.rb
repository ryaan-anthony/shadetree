require "test_helper"

class PricingControllerTest < ActionDispatch::IntegrationTest
  # Disable fixture loading for this test since it's a simple marketing page
  self.use_transactional_tests = true

  # Happy Path Tests

  test "should get index" do
    get pricing_path
    assert_response :success
  end

  test "should render index template" do
    get pricing_path
    assert_template :index
  end

  test "should use marketing layout" do
    get pricing_path
    assert_template layout: "layouts/marketing"
  end

  # Content Validation Tests

  test "index should display pricing hero section" do
    get pricing_path
    assert_select "h1", text: /Simple Pricing That/
    assert_select "h1 span", text: "Grows With You"
  end

  test "index should display all three pricing tiers" do
    get pricing_path
    assert_select "h3", text: "Solo"
    assert_select "h3", text: "Crew"
    assert_select "h3", text: "Fleet"
  end

  test "index should display pricing amounts" do
    get pricing_path
    # Check for monthly prices
    assert_match /\$9\.99/, response.body
    assert_match /\$39\.99/, response.body
    assert_match /\$79\.99/, response.body
  end

  test "index should include billing toggle functionality" do
    get pricing_path
    assert_select "button#billing-toggle"
    assert_select "span#monthly-label", text: "Monthly"
    assert_select "span#annual-label", text: /Annual/
  end

  test "index should display Get Started links for all tiers" do
    get pricing_path
    assert_select "a[href*='#{new_user_registration_path}']", minimum: 3
  end

  test "index should include tier parameter in signup links" do
    get pricing_path
    assert_select "a[href='#{new_user_registration_path(tier: 'solo')}']"
    assert_select "a[href='#{new_user_registration_path(tier: 'crew')}']"
    assert_select "a[href='#{new_user_registration_path(tier: 'fleet')}']"
  end

  test "index should mark Crew plan as most popular" do
    get pricing_path
    assert_select "span", text: "Most Popular"
  end

  test "index should display feature comparison table" do
    get pricing_path
    assert_select "h2", text: "Compare All Features"
    assert_select "table"
    assert_select "thead th", text: "Features"
    assert_select "thead th", text: "Solo"
    assert_select "thead th", text: "Crew"
    assert_select "thead th", text: "Fleet"
  end

  test "index should display FAQ section" do
    get pricing_path
    assert_select "h2", text: "Frequently Asked Questions"
    assert_select "h3", text: "Do you offer a free trial?"
    assert_select "h3", text: "Can I change plans anytime?"
    assert_select "h3", text: "Are there any setup fees or contracts?"
    assert_select "h3", text: "What payment methods do you accept?"
  end

  test "index should display final CTA section" do
    get pricing_path
    assert_select "h2", text: "Ready to Get Started?"
    assert_select "a[href='#{new_user_registration_path}']", text: "Start Free Trial"
    assert_select "a[href='#{contact_path}']", text: "Contact Sales"
  end

  test "index should include pricing toggle javascript" do
    get pricing_path
    assert_match /document\.getElementById\('billing-toggle'\)/, response.body
    assert_match /isAnnual/, response.body
  end

  test "index should include annual pricing data" do
    get pricing_path
    # Check for annual prices in JavaScript
    assert_match /\$7\.99/, response.body  # Solo annual
    assert_match /\$31\.99/, response.body  # Crew annual
    assert_match /\$63\.99/, response.body  # Fleet annual
  end

  test "index should display savings messaging" do
    get pricing_path
    assert_select "span", text: /Save 20%/
    assert_select "div#solo-annual-savings", text: "Save $24/year"
    assert_select "div#crew-annual-savings", text: "Save $96/year"
    assert_select "div#fleet-annual-savings", text: "Save $192/year"
  end

  test "index should include no credit card required messaging" do
    get pricing_path
    assert_match /No credit card required/, response.body
    assert_match /14-day free trial/, response.body
    assert_match /Cancel anytime/, response.body
  end

  # Response Format Tests

  test "index should return HTML by default" do
    get pricing_path
    assert_equal "text/html; charset=utf-8", response.content_type
  end

  # Security Tests

  test "index should not require authentication" do
    # Test that pricing page is publicly accessible
    get pricing_path
    assert_response :success
    assert_not response.redirect?, "Should not redirect to login page"
  end


  # Accessibility Tests

  test "index should have proper heading hierarchy" do
    get pricing_path
    assert_select "h1"
    assert_select "h2"
    assert_select "h3"
  end

  test "index should include proper page title" do
    get pricing_path
    assert_select "title", text: /Shadetree/
  end

  test "index should have proper viewport meta tag" do
    get pricing_path
    assert_select "meta[name='viewport'][content*='width=device-width']"
  end
end
