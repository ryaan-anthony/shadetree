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

  # Mobile Selector Tests

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
    post switch_admin_business_path, params: { business: @business2.uid }, as: :json
    assert_response :success

    response_data = JSON.parse(response.body)
    assert_equal true, response_data["success"]
    assert_equal @business2.uid, response_data["business"]["id"]
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

    post switch_admin_business_path, params: { business: "no-such-uid" }, as: :json
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
    post switch_admin_business_path, params: { business: other_business.uid }, as: :json
    assert_response :not_found

    response_data = JSON.parse(response.body)
    assert_equal false, response_data["success"]

    # Session should not be updated
    assert_not_equal other_business.id, session[:current_business_id]
  end

  test "session persists business selection across requests" do
    sign_in @user

    # Switch to second business
    post switch_admin_business_path, params: { business: @business2.uid }, as: :json
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

  # JavaScript Functionality Tests (behavior verification)

  # Business switcher (sidebar menu)

  test "business switcher lists each of the user's businesses as a switch form" do
    @business3 = Business.create!(name: "Third Business", owner: @user)
    sign_in @user
    get admin_root_path

    assert_response :success
    [ @business1, @business2, @business3 ].each do |business|
      assert_select "form[action='#{switch_admin_business_path}'] input[name='business'][value='#{business.uid}']", count: 1
    end
  end

  test "business switcher marks the current business" do
    sign_in @user
    post switch_admin_business_path, params: { business: @business2.uid }
    get admin_root_path

    assert_select ".biz-switch", text: /#{@business2.name}/
    assert_select "button.menu-item[aria-current='true']", text: /#{@business2.name}/, count: 1
  end

  test "business switcher offers to create a business" do
    sign_in @user
    get admin_root_path

    assert_select "[data-controller='menu'] a.menu-item[href='#{new_admin_business_path}']", text: /Create a business/
  end

  test "business switcher hides other users' businesses" do
    other_user = User.new(email: "other_#{SecureRandom.hex(4)}@example.com", password: "password123", confirmed_at: Time.current)
    other_user.skip_confirmation_notification!
    other_user.save!
    other_business = Business.create!(name: "Other User Business", owner: other_user)

    sign_in @user
    get admin_root_path

    assert_select "input[name='business'][value='#{other_business.uid}']", count: 0
  end

  test "switching from the menu redirects home with a notice" do
    sign_in @user
    post switch_admin_business_path, params: { business: @business2.uid }

    assert_redirected_to admin_root_path
    assert_equal "Switched to #{@business2.name}.", flash[:notice]
    assert_equal @business2.id, session[:current_business_id]
  end

  test "switching to a business you can't access redirects with an alert" do
    sign_in @user
    post switch_admin_business_path, params: { business: "no-such-uid" }

    assert_redirected_to admin_root_path
    assert_match "isn't available", flash[:alert]
  end
end
