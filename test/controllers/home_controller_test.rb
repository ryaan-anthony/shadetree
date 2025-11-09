require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  # Happy Path Tests

  test "should get index" do
    get root_path
    assert_response :success
  end

  test "should render index template" do
    get root_path
    assert_template :index
  end

  test "should use marketing layout" do
    get root_path
    assert_template layout: "layouts/marketing"
  end

  # Content Validation Tests

  test "index should display hero heading" do
    get root_path
    assert_select "h1", text: /Streamline Your/
    assert_select "h1 span", text: "Service Business"
  end

  test "index should display hero tagline" do
    get root_path
    assert_match /Quote it, book it, get paid/, response.body
  end

  test "index should display badge" do
    get root_path
    assert_select "span", text: /Booked and paid in under 60 seconds/
  end

  test "index should display primary CTAs" do
    get root_path
    assert_select "a[href='#{new_user_registration_path}']", text: "Start Free Trial"
    assert_select "a[href='#demo']", text: "Watch 2-Min Demo"
  end

  test "index should display dashboard mockup section" do
    get root_path
    assert_select ".bg-enterprise-navy", minimum: 1
    assert_match /Your Operations Dashboard/, response.body
    assert_match /Multi-Location Support/, response.body
  end

  # Response Format Tests

  test "index should return HTML by default" do
    get root_path
    assert_equal "text/html; charset=utf-8", response.content_type
  end

  # Security Tests

  test "index should not require authentication" do
    get root_path
    assert_response :success
    assert_not response.redirect?, "Should not redirect to login page"
  end

  # Accessibility Tests

  test "index should have proper heading hierarchy" do
    get root_path
    assert_select "h1"
  end

  test "index should include proper page title" do
    get root_path
    assert_select "title", text: /Shadetree/
  end

  test "index should have proper viewport meta tag" do
    get root_path
    assert_select "meta[name='viewport'][content*='width=device-width']"
  end
end

