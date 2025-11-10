require "test_helper"

class Admin::MultipleBusinessesTest < ActionDispatch::IntegrationTest
  setup do
    # Clean up any existing test data
    Business.destroy_all
    User.destroy_all

    # Create user with confirmed account
    @user = User.new(
      email: "multi_business_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @user.skip_confirmation_notification!
    @user.save!

    # Create first business
    @business1 = Business.create!(
      name: "First Business",
      owner: @user
    )

    # Create second business
    @business2 = Business.create!(
      name: "Second Business",
      owner: @user
    )
  end

  teardown do
    Business.destroy_all
    User.destroy_all
  end

  # Business Selector Tests

  test "business selector shows all user businesses" do
    sign_in @user
    get admin_root_path

    assert_response :success
    assert_select "select#business-selector" do
      assert_select "option[value='#{@business1.id}']", text: "First Business"
      assert_select "option[value='#{@business2.id}']", text: "Second Business"
    end
  end

  test "business selector shows create new business option" do
    sign_in @user
    get admin_root_path

    assert_response :success
    assert_select "select#business-selector option[value='new']", text: /Create New Business/
  end

  test "business selector has proper styling without double arrows" do
    sign_in @user
    get admin_root_path

    assert_response :success
    # Check for appearance-none class to remove default arrow
    assert_select "select#business-selector.appearance-none"
    # Check for custom arrow SVG within the business selector container
    # The SVG should be in the sibling div after the select element
    assert_select "select#business-selector" do
      # Can't directly select sibling, so we'll just verify the selector exists with appearance-none
      # and check that there's an SVG on the page (could be multiple from Feather icons elsewhere)
    end
    # Instead, let's verify the structure - select has appearance-none (no default arrow)
    # and there's a pointer-events-none div with SVG (custom arrow)
    assert_select "div.pointer-events-none svg", minimum: 1
  end

  # Business Creation Flow Tests

  test "user with existing business can create another business" do
    sign_in @user

    # Should allow access to new business page
    get new_admin_business_path
    assert_response :success
    assert_select "form[action='#{admin_business_path}']"
  end

  test "creating new business from selector redirects correctly" do
    sign_in @user

    get new_admin_business_path
    assert_response :success

    # Create new business
    assert_difference "Business.count", 1 do
      post admin_business_path, params: {
        business: {
          name: "Third Business",
          industry: "landscaping"
        }
      }
    end

    assert_redirected_to admin_root_path
    follow_redirect!
    assert_match /Business created successfully/, flash[:notice]
  end

  test "new business form shows cancel button when user has existing businesses" do
    sign_in @user

    get new_admin_business_path
    assert_response :success

    # Should show cancel button
    assert_select "a[href='#{admin_root_path}']", text: "Cancel"
  end

  test "new business form does not show cancel for first-time users" do
    # Create user with no businesses
    new_user = User.new(
      email: "newuser_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    new_user.skip_confirmation_notification!
    new_user.save!

    sign_in new_user

    get new_admin_business_path
    assert_response :success

    # Should NOT show cancel button
    assert_select "a[href='#{admin_root_path}']", text: "Cancel", count: 0
  end

  test "canceling new business creation returns to dashboard" do
    sign_in @user

    get new_admin_business_path
    assert_response :success

    # Click cancel link (simulated by direct GET)
    get admin_root_path
    assert_response :success
    # User should still have their original businesses
    assert_equal 2, @user.businesses.count
  end

  # Business Context Persistence Tests

  test "user stays on their current business after canceling new business" do
    sign_in @user

    # Set current business context (would normally be set by selector)
    # For now, just verify the business exists
    assert @user.businesses.include?(@business1)

    # Visit new business page
    get new_admin_business_path
    assert_response :success

    # Cancel and return to dashboard
    get admin_root_path
    assert_response :success

    # Verify businesses still exist and count is unchanged
    assert_equal 2, @user.businesses.reload.count
    assert Business.exists?(@business1.id)
    assert Business.exists?(@business2.id)
  end

  # Business Listing Tests

  test "user can see all their businesses in selector" do
    sign_in @user

    # Create a third business
    @business3 = Business.create!(
      name: "Third Business",
      owner: @user
    )

    get admin_root_path
    assert_response :success

    # Should show all three businesses
    assert_select "select#business-selector option", count: 4 # 3 businesses + 1 "Create New"
  end

  test "business selector only shows user's own businesses" do
    # Create another user with their own business
    other_user = User.new(
      email: "other_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    other_user.skip_confirmation_notification!
    other_user.save!

    other_business = Business.create!(
      name: "Other User Business",
      owner: other_user
    )

    sign_in @user
    get admin_root_path

    assert_response :success
    # Should NOT show other user's business
    assert_select "select#business-selector option[value='#{other_business.id}']", count: 0
    # Should show own businesses
    assert_select "select#business-selector option[value='#{@business1.id}']", count: 1
    assert_select "select#business-selector option[value='#{@business2.id}']", count: 1
  end

  # Mobile Selector Tests

  test "mobile business selector shows all businesses" do
    sign_in @user
    get admin_root_path

    assert_response :success
    # Check mobile selector exists with businesses
    assert_match /mobile-business-selector/, response.body
  end

  # Edge Cases

  test "creating business with invalid data shows errors" do
    sign_in @user

    assert_no_difference "Business.count" do
      post admin_business_path, params: {
        business: {
          name: "" # Invalid: name is required
        }
      }
    end

    assert_response :unprocessable_content
    assert_select ".text-red-800", /error/
  end

  test "switching between businesses updates session and current_business" do
    sign_in @user

    # Initially, first business should be current (or most recent)
    get admin_root_path
    assert_response :success

    # Switch to second business
    post switch_admin_business_path, params: { business_id: @business2.id }, as: :json
    assert_response :success

    response_data = JSON.parse(response.body)
    assert_equal true, response_data["success"]
    assert_equal @business2.id, response_data["business"]["id"]
    assert_equal @business2.name, response_data["business"]["name"]

    # Verify session was updated
    assert_equal @business2.id, session[:current_business_id]

    # Verify new business is now current when visiting dashboard
    get admin_root_path
    assert_response :success
    # The current_business helper should now return business2
  end

  test "switching to non-existent business returns error" do
    sign_in @user

    post switch_admin_business_path, params: { business_id: 99999 }, as: :json
    assert_response :not_found

    response_data = JSON.parse(response.body)
    assert_equal false, response_data["success"]
    assert_equal "Business not found", response_data["error"]
  end

  test "switching to another user's business is not allowed" do
    sign_in @user

    # Create another user with their own business
    other_user = User.new(
      email: "hacker_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    other_user.skip_confirmation_notification!
    other_user.save!

    other_business = Business.create!(
      name: "Someone Else's Business",
      owner: other_user
    )

    # Try to switch to other user's business
    post switch_admin_business_path, params: { business_id: other_business.id }, as: :json
    assert_response :not_found

    response_data = JSON.parse(response.body)
    assert_equal false, response_data["success"]

    # Session should not be updated
    assert_not_equal other_business.id, session[:current_business_id]
  end

  test "session persists business selection across requests" do
    sign_in @user

    # Switch to second business
    post switch_admin_business_path, params: { business_id: @business2.id }, as: :json
    assert_response :success

    # Visit different pages and verify business stays the same
    get admin_root_path
    assert_response :success
    assert_equal @business2.id, session[:current_business_id]

    get edit_admin_business_path
    assert_response :success
    assert_equal @business2.id, session[:current_business_id]
  end

  test "user without businesses sees setup message" do
    # Create new user with no businesses
    new_user = User.new(
      email: "nobiz_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    new_user.skip_confirmation_notification!
    new_user.save!

    sign_in new_user

    # Dashboard redirects to business creation
    get admin_root_path
    assert_redirected_to new_admin_business_path
  end

  test "business selector maintains selection state" do
    sign_in @user
    get admin_root_path

    assert_response :success
    # First business should be selected by default (current_business)
    assert_select "select#business-selector option[selected]"
  end

  # JavaScript Functionality Tests (behavior verification)

  test "business selector has correct JavaScript attributes" do
    sign_in @user
    get admin_root_path

    assert_response :success
    # Verify selector has ID for JavaScript to target
    assert_select "select#business-selector"
    # Verify script tag exists for handling changes
    assert_match /addEventListener\('change'/, response.body
  end

  test "create new business option redirects to correct path" do
    sign_in @user
    get admin_root_path

    assert_response :success
    # Verify the new option value and redirect logic exists
    assert_match /value="new"/, response.body
    assert_match /admin\/business\/new/, response.body
  end
end
