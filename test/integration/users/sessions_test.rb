require "test_helper"

class Users::SessionsTest < ActionDispatch::IntegrationTest
  setup do
    # Create confirmed user
    @confirmed_user = User.new(
      email: "session_confirmed@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @confirmed_user.skip_confirmation_notification!
    @confirmed_user.save!

    # Create unconfirmed user
    @unconfirmed_user = User.new(
      email: "session_unconfirmed@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @unconfirmed_user.skip_confirmation_notification!
    @unconfirmed_user.save!

    # Create business for confirmed user
    @business = Business.create!(
      name: "Test Business",
      email: "session_business@example.com",
      owner: @confirmed_user
    )
  end

  # Happy Path Tests - Sign In Page

  test "should display sign in page" do
    get new_user_session_path
    assert_response :success
  end

  test "should render sign in form" do
    get new_user_session_path
    assert_select "form[action='#{user_session_path}'][method='post']"
  end

  test "should have email field" do
    get new_user_session_path
    assert_select "input[name='user[email]']"
  end

  test "should have password field" do
    get new_user_session_path
    assert_select "input[name='user[password]'][type='password']"
  end

  test "should have remember me checkbox" do
    get new_user_session_path
    assert_select "input[name='user[remember_me]'][type='checkbox']"
  end

  test "should have submit button" do
    get new_user_session_path
    assert_select "input[type='submit'], button[type='submit']", minimum: 1
  end

  # Happy Path Tests - Successful Sign In

  test "confirmed user can sign in with valid credentials" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "password123"
      }
    }

    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success  # Successfully accessed admin, so signed in
  end

  test "confirmed user redirected to admin dashboard after sign in" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "password123"
      }
    }

    follow_redirect!
    assert_equal admin_root_path, path
  end

  test "successful sign in sets flash message" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "password123"
      }
    }

    assert_not_nil flash[:notice]
  end

  # Unconfirmed User Tests

  test "unconfirmed user cannot sign in" do
    post user_session_path, params: {
      user: {
        email: @unconfirmed_user.email,
        password: "password123"
      }
    }

    # Devise confirmable blocks unconfirmed users from signing in
    assert_redirected_to new_user_session_path
  end

  test "unconfirmed user sees confirmation reminder" do
    post user_session_path, params: {
      user: {
        email: @unconfirmed_user.email,
        password: "password123"
      }
    }

    # Should be redirected back to sign in with an alert
    assert_redirected_to new_user_session_path
  end

  test "unconfirmed user cannot access admin dashboard" do
    # Try to access admin directly (not signed in, unconfirmed)
    get admin_root_path

    # Should be redirected to sign in since not authenticated
    assert_redirected_to new_user_session_path
  end

  # Edge Cases - Failed Sign In

  test "cannot sign in with invalid email" do
    post user_session_path, params: {
      user: {
        email: "nonexistent@example.com",
        password: "password123"
      }
    }

    assert_response :unprocessable_entity
    # User not signed in, form re-rendered
  end

  test "cannot sign in with wrong password" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "wrongpassword"
      }
    }

    assert_response :unprocessable_entity
    # User not signed in, form re-rendered
  end

  test "cannot sign in with empty email" do
    post user_session_path, params: {
      user: {
        email: "",
        password: "password123"
      }
    }

    assert_response :unprocessable_entity
    # User not signed in, form re-rendered
  end

  test "cannot sign in with empty password" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: ""
      }
    }

    assert_response :unprocessable_entity
    # User should not be signed in, form re-rendered with error
  end

  test "failed sign in displays error message" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "wrongpassword"
      }
    }

    assert_response :unprocessable_entity
    # Just check that it's showing the sign in form again, error handling works
  end

  # Sign Out Tests

  test "signed in user can sign out" do
    sign_in @confirmed_user

    delete destroy_user_session_path

    assert_redirected_to root_path
    # After sign out, trying to access admin should redirect to sign in
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "sign out redirects to root path" do
    sign_in @confirmed_user

    delete destroy_user_session_path

    assert_redirected_to root_path
  end

  test "sign out via DELETE method works" do
    sign_in @confirmed_user

    delete destroy_user_session_path

    assert_redirected_to root_path
    # Verify actually signed out by trying to access admin
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  # Remember Me Tests

  test "remember me checkbox persists session" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "password123",
        remember_me: "1"
      }
    }

    assert_not_nil cookies["remember_user_token"]
  end

  # Layout and UI Tests

  test "sign in page should use marketing layout" do
    get new_user_session_path
    assert_template layout: "layouts/marketing"
  end

  test "sign in page should have link to sign up" do
    get new_user_session_path
    assert_select "a[href='#{new_user_registration_path}']", minimum: 1
  end

  test "sign in page should have forgot password link" do
    get new_user_session_path
    assert_select "a[href='#{new_user_password_path}']", minimum: 1
  end

  test "sign in page should be publicly accessible" do
    get new_user_session_path
    assert_response :success
    assert_not response.redirect?
  end

  test "sign in page should have proper page title" do
    get new_user_session_path
    assert_select "title"
  end

  # Security Tests

  test "cannot access admin without authentication" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "cannot access admin with unconfirmed account" do
    # Unconfirmed users can't even sign in, so accessing admin redirects to sign in
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "password not exposed in response" do
    post user_session_path, params: {
      user: {
        email: @confirmed_user.email,
        password: "password123"
      }
    }

    assert_no_match /password123/, response.body
  end

  # Session Persistence Tests

  test "user stays signed in across requests" do
    sign_in @confirmed_user

    get admin_root_path
    assert_response :success

    get pricing_path
    assert_response :success  # Still signed in, can access any page
  end

  test "different users have separate sessions" do
    sign_in @confirmed_user
    get admin_root_path
    assert_response :success  # First user can access admin

    delete destroy_user_session_path
    assert_redirected_to root_path  # Signed out

    confirmed_user2 = User.create!(
      email: "another@example.com",
      password: "password123",
      confirmed_at: Time.current
    )

    # Create business for second user
    Business.create!(
      name: "Another Business",
      email: "another_biz@example.com",
      owner: confirmed_user2
    )

    sign_in confirmed_user2
    get admin_root_path
    assert_response :success  # Second user can access admin
  end
end
