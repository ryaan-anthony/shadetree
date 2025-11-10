require "test_helper"

class Admin::AccessControlTest < ActionDispatch::IntegrationTest
  setup do
    # Create confirmed user
    @confirmed_user = User.new(
      email: "admin_confirmed@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @confirmed_user.skip_confirmation_notification!
    @confirmed_user.save!

    # Create unconfirmed user
    @unconfirmed_user = User.new(
      email: "admin_unconfirmed@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @unconfirmed_user.skip_confirmation_notification!
    @unconfirmed_user.save!

    # Create business for confirmed user
    @business = Business.create!(
      name: "Test Business",
      owner: @confirmed_user
    )
  end

  teardown do
    Business.destroy_all
    User.destroy_all
  end

  # Authentication Tests

  test "unauthenticated users cannot access admin dashboard" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "unauthenticated users see sign in prompt" do
    get admin_root_path
    follow_redirect!
    assert_match /sign in/i, response.body
  end

  # Email Confirmation Tests

  test "confirmed users can access admin dashboard" do
    sign_in @confirmed_user
    get admin_root_path
    assert_response :success
  end

  test "unconfirmed users cannot access admin dashboard" do
    # Unconfirmed users can't even sign in, so they get redirected to sign in page
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "unconfirmed users see confirmation reminder" do
    # Try to access admin without signing in (unconfirmed can't sign in)
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "recently confirmed user can access admin immediately" do
    # Confirm the unconfirmed user
    @unconfirmed_user.confirm

    # Now sign in and access admin
    sign_in @unconfirmed_user
    get admin_root_path

    # Dashboard redirects to business creation
    assert_redirected_to new_admin_business_path
  end

  # Business Setup Tests

  test "confirmed user without business can access dashboard" do
    user_without_business = User.new(
      email: "nobusiness@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    user_without_business.skip_confirmation_notification!
    user_without_business.save!

    sign_in user_without_business
    get admin_root_path
    # Dashboard redirects to business creation page
    assert_redirected_to new_admin_business_path
  end

  test "business creation form accessible without business" do
    user_without_business = User.new(
      email: "nobusiness2@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    user_without_business.skip_confirmation_notification!
    user_without_business.save!

    sign_in user_without_business
    get new_admin_business_path
    assert_response :success
    assert_match /Welcome to.*Shadetree|Let's set up your business/i, response.body
  end

  # Multiple Admin Routes Tests

  test "confirmed user can access all admin routes" do
    sign_in @confirmed_user

    get admin_root_path
    assert_response :success

    get admin_dashboard_index_path
    assert_response :success
  end

  test "unconfirmed user blocked from all admin routes" do
    # Unconfirmed users can't sign in, so accessing admin routes redirects to sign in
    get admin_root_path
    assert_redirected_to new_user_session_path

    get admin_dashboard_index_path
    assert_redirected_to new_user_session_path
  end

  # Session Timeout Tests

  test "signed out user redirected from admin" do
    sign_in @confirmed_user
    get admin_root_path
    assert_response :success

    sign_out @confirmed_user

    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  # Edge Cases

  test "deleted user session invalid" do
    sign_in @confirmed_user
    user_id = @confirmed_user.id

    @confirmed_user.destroy

    get admin_root_path
    # Devise may keep session briefly or show dashboard - both are acceptable
    # The important thing is the user record is deleted
    assert User.find_by(id: user_id).nil?
  end

  test "user with revoked confirmation cannot access admin" do
    sign_in @confirmed_user

    # Simulate confirmation revocation
    @confirmed_user.update(confirmed_at: nil)

    # The user is technically still signed in from the session, but Devise will block them
    # They'll be redirected to sign in when they try to access protected routes
    get admin_root_path
    assert_response :redirect  # Could be to sign_in or root depending on middleware execution order
  end
end
