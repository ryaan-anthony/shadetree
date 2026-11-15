require "test_helper"

# ACC-02: creating businesses, switching, and losing access.
class Admin::BusinessesAndSwitchingTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one) # owner of business one, technician in business two
  end

  test "a user with no memberships is sent to set up a business" do
    loner = User.create!(email: "loner@example.com", password: "password123", confirmed_at: Time.current)
    sign_in loner
    get admin_root_path
    assert_redirected_to new_admin_business_path
    follow_redirect!
    assert_select "h1", "Set up your business"
    assert_select "form input:not([type=hidden]):not([type=submit]), form select", 2
  end

  test "setup needs a name and an industry" do
    sign_in @user
    post admin_business_path, params: { business: { name: "", industry: "" } }
    assert_response :unprocessable_content
    assert_select "#business_name[aria-invalid='true']"
    assert_select "#business_industry[aria-invalid='true']"
  end

  test "creating a business makes you its owner and switches to it" do
    sign_in @user
    post admin_business_path, params: { business: { name: "Second Shop", industry: "cleaning", email: "ignored@example.com" } }
    business = Business.find_by!(name: "Second Shop")
    assert_redirected_to admin_root_path
    assert_equal "owner", business.business_users.find_by(user: @user).role
    assert_nil business.email, "only name and industry are taken at setup"
    follow_redirect!
    assert_select ".biz-switch", /Second Shop/
  end

  test "the switcher shows the current business and offers to create another" do
    sign_in @user
    get admin_root_path
    assert_select ".biz-switch .biz-logo"
    assert_select "a.menu-item[href='#{new_admin_business_path}']"
  end

  test "the logo replaces initials once set" do
    businesses(:one).update!(logo_url: "https://example.com/logo.png")
    sign_in @user
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    get admin_root_path
    assert_select ".biz-switch .biz-logo img[src='https://example.com/logo.png']"
  end

  test "the choice persists across sessions and devices" do
    sign_in @user
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_equal businesses(:two).id, @user.reload.last_business_id

    other_device = open_session
    other_device.post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    other_device.get admin_root_path
    assert_match businesses(:two).name, other_device.response.body[/class="biz-switch".*?<\/button>/m]
  end

  test "switching needs CSRF protection" do
    ActionController::Base.allow_forgery_protection = true
    sign_in @user
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "losing access to the current business moves you to another one, with a message" do
    sign_in @user
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    business_users(:one_member_of_two).update!(active: false)

    get admin_root_path
    assert_response :success
    assert_select ".biz-switch", /#{businesses(:one).name}/
    assert_select "#flash", /no longer have access/
  end

  test "losing your only business sends you to setup" do
    user = users(:two)
    sign_in user
    get admin_root_path
    membership = user.business_users.sole
    business_users(:one_member_of_two).update!(role: "owner") # someone else stays owner
    membership.update!(active: false)

    get admin_root_path
    assert_redirected_to new_admin_business_path
  end

  test "another business's data stays out of reach while switching" do
    stranger = Business.create!(name: "Stranger Co", owner: users(:two))
    sign_in @user
    post switch_admin_business_path, params: { business: stranger.uid }
    assert_equal "That business isn't available to you.", flash[:alert]
    get admin_root_path
    assert_no_match "Stranger Co", response.body
  end
end
