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

  def remembered_browser(user_agent)
    open_session.tap do |s|
      s.post user_session_path, params: { user: { email: @user.email, password: "password123", remember_me: "1" } }, headers: { "User-Agent" => user_agent }
      assert s.cookies["remember_user_token"].present?
    end
  end

  # The browser was closed and opened again: only its remember-me cookies are left.
  def reopen(browser) = browser.cookies.delete("_shadetree_session")

  test "signing out another browser ends it on its next request; the others stay remembered" do
    phone = remembered_browser(IPHONE_SAFARI)
    laptop = remembered_browser(MAC_CHROME)
    phone_session = @user.user_sessions.find_by!(user_agent: IPHONE_SAFARI)
    laptop.delete user_browser_session_path(phone_session)
    assert_equal "Signed out of Safari on iPhone.", laptop.flash[:notice]
    assert_not phone_session.reload.active?
    assert_not_nil @user.reload.remember_created_at

    phone.get admin_root_path
    phone.assert_redirected_to new_user_session_path
    assert_match "signed out from another device", phone.flash[:alert]
    assert_not_nil @user.reload.remember_created_at, "signing the ended browser out doesn't cancel remember-me elsewhere (#403)"
    assert phone.cookies["remember_user_token"].blank?

    reopen(laptop)
    laptop.get edit_user_registration_path, headers: { "User-Agent" => MAC_CHROME }
    assert_equal 200, laptop.response.status, "the laptop is still remembered"
    assert_equal [ MAC_CHROME ], @user.user_sessions.active.pluck(:user_agent)
  end

  test "a signed-out browser holding a remember-me cookie can't sign itself back in" do
    phone = remembered_browser(IPHONE_SAFARI)
    stolen = phone.cookies.to_hash.slice("remember_user_token", "remembered_session")
    laptop = remembered_browser(MAC_CHROME)
    laptop.delete user_browser_session_path(@user.user_sessions.find_by!(user_agent: IPHONE_SAFARI))

    reopen(phone)
    phone.get admin_root_path, headers: { "User-Agent" => IPHONE_SAFARI }
    phone.assert_redirected_to new_user_session_path
    assert_match "signed out from another device", phone.flash[:alert]
    assert phone.cookies["remember_user_token"].blank?

    copy = open_session # its cookies copied before it was signed out, without its browser id
    stolen.each { |name, value| copy.cookies[name] = value }
    copy.get admin_root_path
    copy.assert_redirected_to new_user_session_path
    copy.get "/"
    assert_equal 200, copy.response.status, "public pages still show"
    assert_equal [ MAC_CHROME ], @user.user_sessions.active.pluck(:user_agent)
    assert_not_nil @user.reload.remember_created_at
  end

  test "a remembered browser comes back to the session it remembered, and keeps being remembered" do
    laptop = remembered_browser(MAC_CHROME)
    remembered = @user.user_sessions.sole
    2.times do
      reopen(laptop)
      travel 10.minutes
      laptop.get edit_user_registration_path, headers: { "User-Agent" => MAC_CHROME }
      assert_equal 200, laptop.response.status
      laptop.assert_select "#browser-sessions li", /Chrome on Mac.*This browser/m
    end
    assert_equal [ remembered ], @user.user_sessions.active.to_a
    assert_in_delta Time.current, remembered.reload.last_active_at, 5
  end

  test "tabs reopening at once all come back through remember-me" do
    laptop = remembered_browser(MAC_CHROME)
    reopen(laptop)
    other_tab = open_session # sends the same cookies, before the first tab's answer arrives
    laptop.cookies.to_hash.each { |name, value| other_tab.cookies[name] = value }
    [ laptop, other_tab ].each do |tab|
      tab.get admin_root_path, headers: { "User-Agent" => MAC_CHROME }
      assert_not_equal new_user_session_url, tab.response.location
      assert_nil tab.flash[:alert]
    end
    assert_equal 1, @user.user_sessions.active.count
  end

  test "an ended browser reopened on the sign-in page sees it after at most one redirect" do
    phone = remembered_browser(IPHONE_SAFARI)
    laptop = remembered_browser(MAC_CHROME)
    laptop.delete user_browser_session_path(@user.user_sessions.find_by!(user_agent: IPHONE_SAFARI))
    reopen(phone)
    phone.get new_user_session_path
    phone.follow_redirect! if phone.response.redirect?
    assert_equal 200, phone.response.status
    assert_match "Sign in", phone.response.body
  end

  test "remember-me from before sessions were remembered per browser needs one sign-in" do
    laptop = remembered_browser(MAC_CHROME)
    laptop.cookies.delete("remembered_session")
    reopen(laptop)
    assert_no_difference -> { @user.user_sessions.count } do
      laptop.get admin_root_path
    end
    laptop.assert_redirected_to new_user_session_path
  end

  test "signing out, or out everywhere, ends remember-me on every browser" do
    phone = remembered_browser(IPHONE_SAFARI)
    laptop = remembered_browser(MAC_CHROME)
    tablet = remembered_browser("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) Safari/604.1")
    laptop.post sign_out_everywhere_path
    [ phone, tablet ].each do |browser|
      reopen(browser)
      browser.get admin_root_path
      browser.assert_redirected_to new_user_session_path
    end

    phone = remembered_browser(IPHONE_SAFARI)
    tablet = remembered_browser("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) Safari/604.1")
    tablet.delete destroy_user_session_path
    assert_nil @user.reload.remember_created_at, "Sign out still cancels remember-me everywhere"
    assert tablet.cookies["remember_user_token"].blank?
    reopen(phone)
    phone.get admin_root_path
    phone.assert_redirected_to new_user_session_path
  end

  test "signing in again in the same browser replaces its old session" do
    laptop = browser(MAC_CHROME)
    laptop.delete destroy_user_session_path
    laptop.post user_session_path, params: { user: { email: @user.email, password: "password123" } }, headers: { "User-Agent" => MAC_CHROME }
    assert_equal 1, @user.user_sessions.active.count
    stale = @user.user_sessions.active.first
    laptop.cookies.delete("_shadetree_session")
    laptop.post user_session_path, params: { user: { email: @user.email, password: "password123" } }, headers: { "User-Agent" => MAC_CHROME }
    assert_not stale.reload.active?, "the browser's earlier session is replaced, not listed twice"
    assert_equal 1, @user.user_sessions.active.count
  end

  test "a browser with no session record is signed out, not given a new one" do
    sign_in @user
    get edit_user_registration_path
    UserSession.delete_all # as if its record were gone
    get edit_user_registration_path
    assert_redirected_to new_user_session_path
    assert_equal 0, UserSession.count
  end

  test "a password reset ends every other browser's session in the list" do
    phone = browser(IPHONE_SAFARI)
    token = @user.send_reset_password_instructions
    reset = open_session
    reset.put user_password_path, params: { user: { reset_password_token: token, password: "brand new phrase", password_confirmation: "brand new phrase" } }
    assert_equal 1, @user.user_sessions.active.count, "only the browser that reset"
    phone.get admin_root_path
    phone.assert_redirected_to new_user_session_path
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
    laptop.get edit_user_registration_path
    assert_equal 200, laptop.response.status
    phone.get admin_root_path
    phone.assert_redirected_to new_user_session_path

    phone = browser(IPHONE_SAFARI)
    laptop.put user_registration_path, params: { user: { current_password: "password123", password: "a brand new phrase", first_name: @user.first_name } }
    assert_equal [ MAC_CHROME ], @user.user_sessions.active.pluck(:user_agent)
    laptop.get edit_user_registration_path
    assert_equal 200, laptop.response.status
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
    sign_out :user
    sign_in User.create!(email: "new@example.com", password: "password123", first_name: "New", confirmed_at: Time.current)
    get edit_user_registration_path
    assert_select "a[href=?]", settings_admin_notifications_path, 0
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
