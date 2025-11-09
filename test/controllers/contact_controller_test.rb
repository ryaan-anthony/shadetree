require "test_helper"

class ContactControllerTest < ActionDispatch::IntegrationTest
  # Happy Path Tests - GET

  test "should get index" do
    get contact_path
    assert_response :success
  end

  test "should render index template" do
    get contact_path
    assert_template :index
  end

  test "should use marketing layout" do
    get contact_path
    assert_template layout: "layouts/marketing"
  end

  # Content Validation Tests

  test "index should display contact heading" do
    get contact_path
    assert_select "h2", text: "Get in touch"
  end

  test "index should display description" do
    get contact_path
    assert_match /Have questions about Shadetree/, response.body
  end

  test "index should display contact form" do
    get contact_path
    assert_select "form[action='#{contact_path}'][method='post']"
  end

  test "index should have all required form fields" do
    get contact_path
    assert_select "input[name='name']"
    assert_select "input[name='email']"
    assert_select "input[name='company']"
    assert_select "input[name='phone']"
    assert_select "textarea[name='message']"
  end

  test "index should have submit button" do
    get contact_path
    assert_select "input[type='submit']", minimum: 1
  end

  test "index should set custom page title" do
    get contact_path
    assert_select "title", text: /Contact Us/
  end

  # Happy Path Tests - POST

  test "should create contact submission with valid params" do
    post contact_path, params: {
      name: "John Doe",
      email: "john@example.com",
      company: "Test Company",
      phone: "555-1234",
      message: "This is a test message"
    }

    assert_redirected_to contact_path
    assert_equal "Thank you for your message! We'll get back to you soon.", flash[:notice]
  end

  test "should handle submission with minimal params" do
    post contact_path, params: {
      name: "Jane Smith",
      email: "jane@example.com",
      message: "Quick question"
    }

    assert_redirected_to contact_path
    assert_not_nil flash[:notice]
  end

  # Flash Message Tests

  test "should display flash notice after form submission" do
    post contact_path, params: {
      name: "Test User",
      email: "test@example.com",
      message: "Test"
    }

    follow_redirect!
    assert_select ".bg-green-50", text: /Thank you for your message/
  end

  # Response Format Tests

  test "index should return HTML by default" do
    get contact_path
    assert_equal "text/html; charset=utf-8", response.content_type
  end

  test "create should redirect" do
    post contact_path, params: {
      name: "Test",
      email: "test@test.com",
      message: "Test"
    }

    assert_response :redirect
  end

  # Security Tests

  test "index should not require authentication" do
    get contact_path
    assert_response :success
    assert_not response.redirect?, "Should not redirect to login page"
  end

  test "create should not require authentication" do
    post contact_path, params: {
      name: "Test",
      email: "test@test.com",
      message: "Test"
    }

    assert_response :redirect
  end

  # Accessibility Tests

  test "index should have proper heading hierarchy" do
    get contact_path
    assert_select "h2"
  end

  test "index should have proper viewport meta tag" do
    get contact_path
    assert_select "meta[name='viewport'][content*='width=device-width']"
  end

  test "form fields should have labels" do
    get contact_path
    assert_select "label[for]", minimum: 4
  end

  # Edge Cases

  test "should handle empty form submission gracefully" do
    post contact_path, params: {}
    assert_redirected_to contact_path
  end

  test "should handle special characters in message" do
    post contact_path, params: {
      name: "Test User",
      email: "test@example.com",
      message: "Special chars: <script>alert('test')</script> & symbols"
    }

    assert_redirected_to contact_path
  end
end
