require "test_helper"

class Users::SignInTest < ActionDispatch::IntegrationTest
  def sign_in_with(email, password, remember: "0")
    post user_session_path, params: { user: { email:, password:, remember_me: remember } }
  end

  test "the page offers remember me, reset and sign up" do
    get new_user_session_path
    assert_select "input[type=checkbox][name='user[remember_me]']"
    assert_select "a[href='#{new_user_password_path}']"
    assert_select "a[href='#{new_user_registration_path}']"
  end

  test "members land on their dashboard; users without a business land in setup" do
    sign_in_with users(:one).email, "password123"
    assert_redirected_to admin_root_path

    delete destroy_user_session_path
    loner = User.create!(email: "loner@example.com", password: "password123", confirmed_at: Time.current)
    sign_in_with loner.email, "password123"
    assert_redirected_to new_admin_business_path
  end

  test "unconfirmed users can sign in and work, with a banner" do
    user = users(:unconfirmed)
    Business.create!(name: "Unconfirmed Co", owner: user)
    sign_in_with user.email, "password123"
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_select "#confirm-email-banner form[action='#{resend_users_confirmation_path}']"
  end

  test "wrong password and unknown email give the same message" do
    sign_in_with users(:one).email, "wrong password"
    wrong_password = flash[:alert]
    sign_in_with "nobody@example.com", "whatever123"
    assert_equal wrong_password, flash[:alert]
    assert_match(/Invalid email or password/i, wrong_password)
  end

  test "repeated failures lock the account and email an unlock link" do
    user = users(:two)
    assert_emails(1) { Devise.maximum_attempts.times { sign_in_with user.email, "wrong password" } }
    assert user.reload.access_locked?

    sign_in_with user.email, "password123"
    assert_response :unprocessable_entity # still locked, same generic message
    assert_match(/Invalid email or password/i, flash[:alert])

    travel Devise.unlock_in + 1.minute do
      sign_in_with user.email, "password123"
      assert_redirected_to admin_root_path
    end
  end

  test "remember me sets a long-lived cookie" do
    sign_in_with users(:one).email, "password123", remember: "1"
    assert cookies[:remember_user_token].present?
  end

  test "sign out" do
    sign_in users(:one)
    delete destroy_user_session_path
    get admin_root_path
    assert_redirected_to new_user_session_path
  end
end
