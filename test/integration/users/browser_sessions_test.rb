require "test_helper"

# ACC-06: the account page lists where you're signed in and signs other browsers out.
class Users::BrowserSessionsTest < ActionDispatch::IntegrationTest
  MAC_CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
  IPHONE_SAFARI = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  setup { @user = users(:one) }

  def browser(user_agent)
    open_session.tap do |s|
      s.post user_session_path, params: { user: { email: @user.email, password: "password123" } }, headers: { "User-Agent" => user_agent }
    end
  end

  test "each sign-in is listed with its browser, and this one is marked" do
    phone = browser(IPHONE_SAFARI)
    laptop = browser(MAC_CHROME)
    laptop.get edit_user_registration_path, headers: { "User-Agent" => MAC_CHROME }
    laptop.assert_select "#browser-sessions li", 2
    laptop.assert_select "#browser-sessions li", /Chrome on Mac.*This browser/m
    laptop.assert_select "#browser-sessions li", /Safari on iPhone.*Last active/m
    laptop.assert_select "#browser-sessions li", /Chrome on Mac/ do
      laptop.assert_select "button", { text: "Sign out", count: 0 }, "this browser signs out with the usual Sign out"
    end
    assert phone
  end

  test "signing out another browser ends it on its next request, and remember-me everywhere" do
    phone = browser(IPHONE_SAFARI)
    laptop = browser(MAC_CHROME)
    @user.update_columns(remember_created_at: Time.current)
    phone_session = @user.user_sessions.find_by!(user_agent: IPHONE_SAFARI)
    laptop.delete user_browser_session_path(phone_session)
    assert_equal "Signed out of Safari on iPhone.", laptop.flash[:notice]
    assert_not phone_session.reload.active?
    assert_nil @user.reload.remember_created_at

    phone.get admin_root_path
    phone.assert_redirected_to new_user_session_path
    assert_match "signed out from another device", phone.flash[:alert]
    laptop.get admin_root_path
    assert_includes [ 200, 302 ], laptop.response.status
    assert_not_equal new_user_session_url, laptop.response.location
  end

  test "you can't sign out this browser or someone else's from here" do
    laptop = browser(MAC_CHROME)
    mine = @user.user_sessions.last
    laptop.delete user_browser_session_path(mine)
    assert_match "That's this browser", laptop.flash[:alert]
    assert mine.reload.active?

    theirs = UserSession.start!(users(:two), ActionDispatch::TestRequest.create).first
    laptop.delete user_browser_session_path(theirs)
    assert_equal 404, laptop.response.status
    assert theirs.reload.active?
  end

  test "signing out ends the session; signing out everywhere or a new password ends the others" do
    phone = browser(IPHONE_SAFARI)
    laptop = browser(MAC_CHROME)
    tablet = browser("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) Safari/604.1")
    tablet.delete destroy_user_session_path
    assert_not @user.user_sessions.find_by!(user_agent: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) Safari/604.1").active?

    laptop.post sign_out_everywhere_path
    assert_equal [ MAC_CHROME ], @user.user_sessions.active.pluck(:user_agent)
    phone.get admin_root_path
    phone.assert_redirected_to new_user_session_path

    phone = browser(IPHONE_SAFARI)
    laptop.put user_registration_path, params: { user: { current_password: "password123", password: "a brand new phrase", first_name: @user.first_name } }
    assert_equal [ MAC_CHROME ], @user.user_sessions.active.pluck(:user_agent)
    assert phone
  end

  test "quiet sessions drop off the list, then are deleted; activity is noted at most every few minutes" do
    laptop = browser(MAC_CHROME)
    old = UserSession.start!(@user, ActionDispatch::TestRequest.create).first
    old.update_columns(last_active_at: 40.days.ago)
    laptop.get edit_user_registration_path
    laptop.assert_select "#browser-sessions li", 1

    mine = @user.user_sessions.find_by!(user_agent: MAC_CHROME)
    travel 2.minutes do
      laptop.get admin_root_path
      assert_in_delta 2.minutes.ago, mine.reload.last_active_at, 5
    end
    travel 6.minutes do
      laptop.get admin_root_path
      assert_in_delta Time.current, mine.reload.last_active_at, 5
    end
    old.update_columns(last_active_at: 100.days.ago)
    browser(IPHONE_SAFARI)
    assert_not UserSession.exists?(old.id)
  end

  test "team email choices are linked for people in a business" do
    sign_in @user
    get edit_user_registration_path
    assert_select "a[href=?]", settings_admin_notifications_path, "Choose emails"
  end

  test "device labels" do
    { MAC_CHROME => "Chrome on Mac", IPHONE_SAFARI => "Safari on iPhone",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36 Edg/131.0" => "Edge on Windows",
      "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0" => "Firefox on Linux",
      "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36" => "Chrome on Android",
      nil => "A browser" }.each do |ua, label|
      assert_equal label, UserSession.new(user_agent: ua).device_label
    end
  end
end
