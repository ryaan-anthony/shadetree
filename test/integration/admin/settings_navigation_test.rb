require "test_helper"

# #289: Settings has one entry point and four groups; every page keeps its old address, and a
# member only sees the pages their role can open.
class Admin::SettingsNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def groups = css_select("#settings-nav .tabs a").map(&:text)
  def pages = css_select("#settings-nav ul a").map(&:text)
  def current_group = css_select("#settings-nav .tabs a[aria-current]").map(&:text)
  def current_page = css_select("#settings-nav ul a[aria-current=page]").map(&:text)

  def sign_in_as(role = nil, permissions: nil)
    user = if permissions
      custom = as_business(@business) { Role.create!(name: "Role #{SecureRandom.hex(2)}", permissions:) }
      member_with_role(:technician).tap { |u| as_business(@business) { @business.business_users.find_by!(user: u).update!(role: "custom", role_id: custom.id) } }
    else
      member_with_role(role)
    end
    sign_in user
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "/admin/settings opens the first page the member can use" do
    get "/admin/settings"
    assert_redirected_to edit_admin_business_path
    follow_redirect!
    assert_select "h1", "Settings"
    assert_select "nav[aria-label=Primary] a[aria-current=page][href=?]", edit_admin_business_path, /Settings/
  end

  test "four groups, the current one's pages, and every old address still works and lights up Settings" do
    get edit_admin_business_path
    assert_equal [ "Business", "Money", "Messages", "Plan and data" ], groups
    assert_equal [ "Details", "Hours", "Branding", "Request form" ], pages
    assert_equal [ [ "Business" ], [ "Details" ] ], [ current_group, current_page ]

    { edit_admin_business_path(tab: "documents") => [ "Money", "Quotes, jobs & invoices" ], admin_tax_rates_path => [ "Money", "Taxes" ],
      admin_payment_account_path => [ "Money", "Card payments" ], admin_hours_path => [ "Business", "Hours" ],
      edit_admin_business_path(tab: "branding") => [ "Business", "Branding" ], edit_admin_business_path(tab: "request_form") => [ "Business", "Request form" ],
      admin_message_templates_path => [ "Messages", "Emails to clients" ], admin_automations_path => [ "Messages", "Automations" ],
      admin_plan_path => [ "Plan and data", "Plan" ], admin_data_exports_path => [ "Plan and data", "Your data" ] }.each do |path, (group, page)|
      get path
      assert_response :success, path
      assert_equal [ [ group ], [ page ] ], [ current_group, current_page ], path
      assert_select "nav[aria-label=Primary] a[aria-current=page]", /Settings/
    end
  end

  test "Locations shows with a second location, and while adding the first" do
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    get edit_admin_business_path
    assert_not_includes pages, "Locations", "one location: nothing to list"
    get new_admin_location_path
    assert_includes pages, "Locations", "adding one: it's where you are"
    as_business(@business) { Location.create!(name: "North yard") }
    get edit_admin_business_path
    assert_includes pages, "Locations"
  end

  test "an export-only role sees only Your data, and that's where Settings opens" do
    sign_in_as(permissions: %w[export_data])
    get "/admin/settings"
    assert_redirected_to admin_data_exports_path
    follow_redirect!
    assert_equal [ "Plan and data" ], groups
    assert_equal [ "Plan and data" ], css_select("#settings-nav .tabs a[aria-current=page]").map(&:text), "one page: the group is the page"
    assert_select "#settings-nav ul", 0
  end

  test "a role with settings but no export doesn't see Your data" do
    sign_in_as(permissions: %w[business_settings])
    get admin_plan_path
    assert_equal [ "Business", "Money", "Messages", "Plan and data" ], groups
    assert_select "#settings-nav .tabs a[aria-current=page]", "Plan and data"
    assert_not_includes css_select("#settings-nav a").map(&:text), "Your data"
  end

  test "a technician opening /admin/settings is told it isn't available" do
    sign_in_as(:technician)
    get "/admin/settings"
    assert_response :forbidden
    assert_select "h1", /isn't available with your role/
    assert_select "[data-controller~=tip]", 0 # no first-time tip on it (ACC-08)
  end
end
