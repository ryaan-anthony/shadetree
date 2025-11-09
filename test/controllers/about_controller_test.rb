require "test_helper"

class AboutControllerTest < ActionDispatch::IntegrationTest
  # Happy Path Tests

  test "should get index" do
    get about_path
    assert_response :success
  end

  test "should render index template" do
    get about_path
    assert_template :index
  end

  test "should use marketing layout" do
    get about_path
    assert_template layout: "layouts/marketing"
  end

  # Content Validation Tests

  test "index should display hero heading" do
    get about_path
    assert_select "h1", text: /We're on a mission to simplify/
    assert_select "h1 span", text: "service business operations"
  end

  test "index should display badge" do
    get about_path
    assert_select "span", text: /Built by small business owners, for small business owners/
  end

  test "index should display mission statement" do
    get about_path
    assert_match /Shadetree was born from the frustration/, response.body
    assert_match /running a service business should be simple/, response.body
  end

  test "index should display our story section" do
    get about_path
    assert_select "h2", text: "From chaos to clarity"
    assert_match /landscaping business/, response.body
  end

  test "index should set custom page title" do
    get about_path
    assert_select "title", text: /About Us/
  end

  # Response Format Tests

  test "index should return HTML by default" do
    get about_path
    assert_equal "text/html; charset=utf-8", response.content_type
  end

  # Security Tests

  test "index should not require authentication" do
    get about_path
    assert_response :success
    assert_not response.redirect?, "Should not redirect to login page"
  end

  # Accessibility Tests

  test "index should have proper heading hierarchy" do
    get about_path
    assert_select "h1"
    assert_select "h2"
  end

  test "index should have proper viewport meta tag" do
    get about_path
    assert_select "meta[name='viewport'][content*='width=device-width']"
  end
end
