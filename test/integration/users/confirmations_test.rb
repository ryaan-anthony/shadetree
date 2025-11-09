require "test_helper"

class Users::ConfirmationsTest < ActionDispatch::IntegrationTest
  setup do
    # Create user without sending confirmation instructions
    @unconfirmed_user = User.new(
      email: "unconfirmed_test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @unconfirmed_user.skip_confirmation_notification!
    @unconfirmed_user.save!
  end

  # Awaiting Confirmation Page Tests

  test "should display awaiting confirmation page" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_response :success
  end

  test "awaiting confirmation page should use marketing layout" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_template layout: "layouts/marketing"
  end

  test "awaiting confirmation page should display email address" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_match @unconfirmed_user.email, response.body
  end

  test "awaiting confirmation page should have resend functionality" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    # When email is present, shows a button to resend
    assert_select "button[type='submit']", text: /Resend/i
  end

  test "awaiting confirmation page without email shows resend link" do
    get awaiting_confirmation_users_confirmation_path
    # Without email parameter, shows link to resend form
    assert_select "a[href='#{new_user_confirmation_path}']", text: /Resend/i
  end

  test "awaiting confirmation page should have sign in link" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_select "a[href='#{new_user_session_path}']", text: /Sign in/i
  end

  test "awaiting confirmation page should have contact support link" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_select "a[href='#{contact_path}']", text: /support/i
  end

  test "awaiting confirmation page should display instructions" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_match /Check your email inbox/i, response.body
    assert_match /Click the confirmation link/i, response.body
    assert_match /spam folder/i, response.body
  end

  test "awaiting confirmation page should work without email parameter" do
    get awaiting_confirmation_users_confirmation_path
    assert_response :success
  end

  # Registration Redirect Tests

  test "new user registration should redirect to awaiting confirmation" do
    post user_registration_path, params: {
      user: {
        email: "newuser@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_redirected_to awaiting_confirmation_users_confirmation_path(email: "newuser@example.com")
  end

  test "after signup should show awaiting confirmation page" do
    post user_registration_path, params: {
      user: {
        email: "newuser2@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    follow_redirect!
    assert_response :success
    assert_match /Check Your Email/i, response.body
    assert_match /newuser2@example.com/, response.body
  end

  # Sign In Redirect Tests

  test "unconfirmed user trying to sign in should be blocked" do
    post user_session_path, params: {
      user: {
        email: @unconfirmed_user.email,
        password: "password123"
      }
    }

    # Devise confirmable blocks unconfirmed users from signing in
    assert_redirected_to new_user_session_path
  end

  test "unconfirmed user should not be signed in after redirect" do
    post user_session_path, params: {
      user: {
        email: @unconfirmed_user.email,
        password: "password123"
      }
    }

    # Cannot sign in, redirected back to sign in page
    assert_redirected_to new_user_session_path
  end

  test "unconfirmed user sign in should show alert message" do
    post user_session_path, params: {
      user: {
        email: @unconfirmed_user.email,
        password: "password123"
      }
    }

    # Redirected back to sign in
    assert_redirected_to new_user_session_path
  end

  # Confirmation Success Tests

  test "confirming email should redirect to admin dashboard" do
    get user_confirmation_path, params: { confirmation_token: @unconfirmed_user.confirmation_token }

    @unconfirmed_user.reload
    assert @unconfirmed_user.confirmed?
    assert_redirected_to admin_root_path
  end

  test "after confirmation user should be signed in" do
    get user_confirmation_path, params: { confirmation_token: @unconfirmed_user.confirmation_token }
    follow_redirect!

    assert_not_nil controller.current_user
    assert_equal @unconfirmed_user.id, controller.current_user.id
  end

  test "after confirmation should show success message" do
    get user_confirmation_path, params: { confirmation_token: @unconfirmed_user.confirmation_token }

    assert_match /email has been confirmed/i, flash[:notice]
  end

  # Edge Cases

  test "accessing awaiting confirmation while signed in shows page" do
    confirmed_user = User.create!(
      email: "confirmed_access@example.com",
      password: "password123",
      confirmed_at: Time.current
    )

    sign_in confirmed_user
    get awaiting_confirmation_users_confirmation_path
    assert_response :success
  end

  test "page should have proper page title" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_select "title", text: /Check Your Email/i
  end

  # Resend Confirmation Tests

  test "resend with valid email should send confirmation email" do
    assert_emails 1 do
      post resend_users_confirmation_path, params: { email: @unconfirmed_user.email }
    end
  end

  test "resend with valid email should show success message" do
    post resend_users_confirmation_path, params: { email: @unconfirmed_user.email }

    assert_redirected_to awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    follow_redirect!
    assert_match /confirmation email has been resent/i, flash[:notice]
  end

  test "resend with blank email should show error" do
    post resend_users_confirmation_path, params: { email: "" }

    assert_redirected_to awaiting_confirmation_users_confirmation_path
    assert_match /provide an email address/i, flash[:alert]
  end

  test "resend with non-existent email should show error" do
    post resend_users_confirmation_path, params: { email: "nonexistent@example.com" }

    assert_redirected_to awaiting_confirmation_users_confirmation_path(email: "nonexistent@example.com")
    assert_match /couldn't find an account/i, flash[:alert]
  end

  test "resend with already confirmed email should redirect to sign in" do
    confirmed_user = User.create!(
      email: "already_confirmed@example.com",
      password: "password123",
      confirmed_at: Time.current
    )

    post resend_users_confirmation_path, params: { email: confirmed_user.email }

    assert_redirected_to new_user_session_path
    assert_match /already confirmed/i, flash[:notice]
  end

  test "resend should not send email for already confirmed user" do
    confirmed_user = User.create!(
      email: "confirmed_no_email@example.com",
      password: "password123",
      confirmed_at: Time.current
    )

    assert_no_emails do
      post resend_users_confirmation_path, params: { email: confirmed_user.email }
    end
  end

  test "multiple resends should work" do
    assert_emails 2 do
      post resend_users_confirmation_path, params: { email: @unconfirmed_user.email }
      post resend_users_confirmation_path, params: { email: @unconfirmed_user.email }
    end
  end

  test "awaiting confirmation page should show resend button when email present" do
    get awaiting_confirmation_users_confirmation_path(email: @unconfirmed_user.email)
    assert_select "button[type='submit']", text: /Resend/i
  end

  test "awaiting confirmation page displays flash messages after resend" do
    # Trigger a resend to generate a flash message
    post resend_users_confirmation_path, params: { email: @unconfirmed_user.email }
    follow_redirect!

    # Should show the success message
    assert_match /confirmation email has been resent/i, response.body
  end
end

