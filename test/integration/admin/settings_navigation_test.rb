require "test_helper"

# #289: Settings has one entry point and four groups; every page keeps its old address.
class Admin::SettingsNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def groups = css_select("#settings-nav .tabs a").map(&:text)
  def pages = css_select("#settings-nav ul a").map(&:text)
  def current_group = css_select("#settings-nav .tabs a[aria-current=true]").map(&:text)
  def current_page = css_select("#settings-nav ul a[aria-current=page]").map(&:text)

  test "/admin/settings opens Settings" do
    get "/admin/settings"
    assert_redirected_to "/admin/business/edit"
    follow_redirect!
    assert_select "h1", "Settings"
  end

  test "four groups, the current one's pages, and every old address still works" do
    get edit_admin_business_path
    assert_equal [ "Business", "Money", "Messages", "Plan and data" ], groups
    assert_equal [ "Details", "Hours", "Branding", "Request form" ], pages
    assert_equal [ [ "Business" ], [ "Details" ] ], [ current_group, current_page ]

    { edit_admin_business_path(tab: "documents") => [ "Money", "Quotes, jobs & invoices" ], admin_tax_rates_path => [ "Money", "Taxes" ],
      admin_payment_account_path => [ "Money", "Online payments" ], admin_hours_path => [ "Business", "Hours" ],
      edit_admin_business_path(tab: "branding") => [ "Business", "Branding" ], edit_admin_business_path(tab: "request_form") => [ "Business", "Request form" ],
      admin_message_templates_path => [ "Messages", "Emails to clients" ], admin_automations_path => [ "Messages", "Automations" ],
      admin_plan_path => [ "Plan and data", "Plan" ], admin_data_exports_path => [ "Plan and data", "Your data" ] }.each do |path, (group, page)|
      get path
      assert_response :success, path
      assert_equal [ [ group ], [ page ] ], [ current_group, current_page ], path
    end
  end

  test "pages a member can't use aren't listed" do
    admin = member_with_role(:admin)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_plan_path
    assert_not_includes pages, "Your data" unless as_business(@business) { @business.business_users.find_by(user: admin).can?(:export_data) }
    assert_not_includes css_select("#settings-nav a").map(&:text), "Locations", "one location: no Locations page"
  end
end
