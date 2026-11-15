require "test_helper"

class Users::AccountTest < ActionDispatch::IntegrationTest
  test "password reset works end to end and the token expires" do
    user = users(:one)
    assert_emails(1) { post user_password_path, params: { user: { email: user.email } } }
    token = ActionMailer::Base.deliveries.last.body.encoded[/reset_password_token=([^"&\s<]+)/, 1]
    assert token

    put user_password_path, params: { user: { reset_password_token: token, password: "brand new phrase", password_confirmation: "brand new phrase" } }
    assert user.reload.valid_password?("brand new phrase")
    delete destroy_user_session_path # a successful reset signs you in

    user2 = users(:two)
    raw = user2.send_reset_password_instructions
    travel Devise.reset_password_within + 1.minute do
      put user_password_path, params: { user: { reset_password_token: raw, password: "another phrase!", password_confirmation: "another phrase!" } }
      assert_response :unprocessable_entity
      assert_not user2.reload.valid_password?("another phrase!")
    end
  end

  test "reset requests don't reveal whether an account exists" do
    post user_password_path, params: { user: { email: users(:one).email } }
    known = flash[:notice]
    post user_password_path, params: { user: { email: "nobody@example.com" } }
    assert_equal known, flash[:notice]
  end

  test "resend confirmation doesn't reveal accounts when signed out" do
    post resend_users_confirmation_path, params: { email: users(:unconfirmed).email }
    known = flash[:notice]
    post resend_users_confirmation_path, params: { email: "nobody@example.com" }
    assert_equal known, flash[:notice]
  end

  test "signed-in unconfirmed users can resend their own link" do
    sign_in users(:unconfirmed)
    assert_emails(1) { post resend_users_confirmation_path }
    assert_match users(:unconfirmed).email, flash[:notice]
  end

  test "confirming signs you in and sends you on" do
    user = users(:unconfirmed)
    raw, enc = Devise.token_generator.generate(User, :confirmation_token)
    user.update_columns(confirmation_token: enc, confirmation_sent_at: Time.current)
    get user_confirmation_path(confirmation_token: raw)
    assert user.reload.confirmed?
    assert_redirected_to new_admin_business_path
  end

  test "sign out of all other devices keeps this session and kills the others" do
    user = users(:one)
    other = open_session
    other.post user_session_path, params: { user: { email: user.email, password: "password123", remember_me: "1" } }
    other.get admin_root_path
    assert_equal 200, other.response.status

    sign_in user
    post sign_out_everywhere_path
    assert_redirected_to edit_user_registration_path

    get admin_root_path
    assert_response :success
    other.get admin_root_path
    assert_equal 302, other.response.status
    assert_match new_user_session_path, other.response.location
  end

  test "changing the profile needs the current password" do
    sign_in users(:one)
    put user_registration_path, params: { user: { first_name: "Johnny", current_password: "nope" } }
    assert_response :unprocessable_entity
    put user_registration_path, params: { user: { first_name: "Johnny", current_password: "password123" } }
    assert_equal "Johnny", users(:one).reload.first_name
  end

  test "a bad confirmation link explains itself" do
    get user_confirmation_path(confirmation_token: "nope")
    assert_select ".banner-danger", /confirmation link didn't work/
  end

  test "a bad unlock link explains itself" do
    get user_unlock_path(unlock_token: "nope")
    assert_select ".banner-danger", /unlock link didn't work/
  end
end
