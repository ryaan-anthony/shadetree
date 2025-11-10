require "test_helper"

class Users::RegistrationsTest < ActionDispatch::IntegrationTest
  setup do
    @user_params = {
      user: {
        email: "newuser@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
  end

  # Happy Path Tests - Sign Up

  test "should display sign up page" do
    get new_user_registration_path
    assert_response :success
  end

  test "should render sign up form" do
    get new_user_registration_path
    assert_select "form[action='#{user_registration_path}'][method='post']"
  end

  test "should have email field" do
    get new_user_registration_path
    assert_select "input[name='user[email]'][type='email']"
  end

  test "should have password field" do
    get new_user_registration_path
    assert_select "input[name='user[password]'][type='password']"
  end

  test "should have password confirmation field" do
    get new_user_registration_path
    assert_select "input[name='user[password_confirmation]'][type='password']"
  end

  test "should have submit button" do
    get new_user_registration_path
    assert_select "input[type='submit'], button[type='submit']", minimum: 1
  end

  test "should create new user with valid params" do
    assert_difference("User.count", 1) do
      post user_registration_path, params: @user_params
    end

    user = User.last
    assert_equal "newuser@example.com", user.email
    assert_not_nil user.encrypted_password
  end

  test "new user should not be confirmed" do
    post user_registration_path, params: @user_params

    user = User.last
    assert_nil user.confirmed_at
    assert_not user.confirmed?
  end

  test "should send confirmation email on registration" do
    assert_emails 1 do
      post user_registration_path, params: @user_params
    end
  end

  test "should redirect to awaiting confirmation after sign up" do
    post user_registration_path, params: @user_params
    assert_redirected_to awaiting_confirmation_users_confirmation_path(email: "newuser@example.com")
  end

  test "should display awaiting confirmation page after sign up" do
    post user_registration_path, params: @user_params
    follow_redirect!
    assert_match /Check Your Email/i, response.body
  end

  # Edge Cases - Validation Errors

  test "should not create user without email" do
    @user_params[:user][:email] = ""

    assert_no_difference("User.count") do
      post user_registration_path, params: @user_params
    end

    assert_response :unprocessable_content
  end

  test "should not create user with invalid email" do
    @user_params[:user][:email] = "invalid-email"

    assert_no_difference("User.count") do
      post user_registration_path, params: @user_params
    end

    assert_response :unprocessable_content
  end

  test "should not create user without password" do
    @user_params[:user][:password] = ""
    @user_params[:user][:password_confirmation] = ""

    assert_no_difference("User.count") do
      post user_registration_path, params: @user_params
    end

    assert_response :unprocessable_content
  end

  test "should not create user with short password" do
    @user_params[:user][:password] = "short"
    @user_params[:user][:password_confirmation] = "short"

    assert_no_difference("User.count") do
      post user_registration_path, params: @user_params
    end

    assert_response :unprocessable_content
  end

  test "should not create user with mismatched passwords" do
    @user_params[:user][:password_confirmation] = "different123"

    assert_no_difference("User.count") do
      post user_registration_path, params: @user_params
    end

    assert_response :unprocessable_content
  end

  test "should not create user with duplicate email" do
    # Create first user
    post user_registration_path, params: @user_params

    # Try to create second user with same email
    assert_no_difference("User.count") do
      post user_registration_path, params: @user_params
    end

    assert_response :unprocessable_content
  end

  test "should display error messages for invalid registration" do
    @user_params[:user][:email] = ""
    post user_registration_path, params: @user_params

    assert_response :unprocessable_content
    assert_match /error|blank|invalid/i, response.body
  end

  # Email Confirmation Tests

  test "should confirm user account with valid token" do
    post user_registration_path, params: @user_params
    user = User.last

    get user_confirmation_path, params: { confirmation_token: user.confirmation_token }

    user.reload
    assert user.confirmed?
    assert_not_nil user.confirmed_at
  end

  test "should not confirm user with invalid token" do
    post user_registration_path, params: @user_params
    user = User.last

    get user_confirmation_path, params: { confirmation_token: "invalid_token" }

    user.reload
    assert_not user.confirmed?
  end

  test "should allow resending confirmation email" do
    post user_registration_path, params: @user_params
    user = User.last

    assert_emails 1 do
      post user_confirmation_path, params: { user: { email: user.email } }
    end
  end

  # Layout and UI Tests

  test "sign up page should use marketing layout" do
    get new_user_registration_path
    assert_template layout: "layouts/marketing"
  end

  test "sign up page should have link to sign in" do
    get new_user_registration_path
    assert_select "a[href='#{new_user_session_path}']", minimum: 1
  end

  test "sign up page should be publicly accessible" do
    get new_user_registration_path
    assert_response :success
    assert_not response.redirect?
  end

  test "sign up page should have proper page title" do
    get new_user_registration_path
    # Page uses marketing layout which has "Shadetree - Job & Quote Software for the Rest of Us"
    assert_select "title"
  end

  # Security Tests

  test "should encrypt password" do
    post user_registration_path, params: @user_params
    user = User.last

    assert_not_equal "password123", user.encrypted_password
    assert user.valid_password?("password123")
  end

  test "should not expose password in response" do
    post user_registration_path, params: @user_params

    assert_no_match /password123/, response.body
  end
end
