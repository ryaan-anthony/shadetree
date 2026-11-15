require "test_helper"

class Users::SignUpTest < ActionDispatch::IntegrationTest
  def sign_up(**overrides)
    post user_registration_path, params: { user: {
      first_name: "Ana", last_name: "Silva", email: "ana@example.com",
      password: "long enough phrase", terms_of_service: "1"
    }.merge(overrides) }
  end

  test "the form asks for name, email, password and terms only" do
    get new_user_registration_path
    assert_response :success
    assert_select "form input:not([type=hidden]):not([type=submit])", 5 # first, last, email, password, terms
    assert_select "input#user_password[minlength='10'][autocomplete='new-password']"
    assert_select "[data-controller='password-strength']"
    assert_select "a[href='#{terms_path}']"
    assert_select "input[name='user[password_confirmation]']", count: 0
  end

  test "signing up signs you in, sends a confirmation and lands in business setup" do
    assert_emails(1) { sign_up }
    user = User.find_by!(email: "ana@example.com")
    assert_redirected_to new_admin_business_path
    assert_equal [ "Ana", "Silva" ], [ user.first_name, user.last_name ]
    assert_not user.confirmed?
    assert_not_nil user.terms_accepted_at

    follow_redirect!
    assert_response :success
    assert_select "#confirm-email-banner", /Confirm your email/
  end

  test "terms must be accepted" do
    assert_no_difference("User.count") { sign_up(terms_of_service: "0") }
    assert_response :unprocessable_entity
    assert_select ".error-text", /must be accepted/
  end

  test "terms can't be skipped by leaving the field out" do
    assert_no_difference("User.count") do
      post user_registration_path, params: { user: { first_name: "Ana", email: "ana@example.com", password: "long enough phrase" } }
    end
    assert_response :unprocessable_entity
  end

  test "Devise emails use the branded layout" do
    sign_up
    mail = ActionMailer::Base.deliveries.last
    assert_match "Confirm your email", mail.body.to_s
    assert_match "activity on your Shadetree account", mail.body.to_s
  end

  test "name is required and passwords need 10 characters" do
    assert_no_difference("User.count") { sign_up(first_name: "", password: "short") }
    assert_select "#user_first_name[aria-invalid='true']"
    assert_select "#user_password[aria-invalid='true']"
  end

  test "duplicate emails are rejected" do
    assert_no_difference("User.count") { sign_up(email: users(:one).email) }
    assert_response :unprocessable_entity
  end
end
