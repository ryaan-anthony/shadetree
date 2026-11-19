require "test_helper"

# CAT-07: Settings → Locations, hidden until a second location exists.
class Admin::LocationsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def branch(business: @business, **attrs) = as_business(business) { Location.create!(name: "North yard", **attrs) }

  test "only owners and admins manage locations" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_location_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_locations_path, params: { location: { name: "Somewhere #{SecureRandom.hex(2)}" } } }
  end

  test "a single-location business sees nothing about locations except a way in on plans that have them" do
    get edit_admin_business_path
    assert_select "nav.tabs a", { text: "Locations", count: 0 }
    assert_select "a[href='#{new_admin_location_path}']", "Add a location"
    get admin_hours_path
    assert_select "nav[aria-label=Location]", 0
    get admin_locations_path
    assert_redirected_to edit_admin_business_path

    @business.update!(plan_overrides: {})
    get edit_admin_business_path
    assert_select "a[href='#{new_admin_location_path}']", 0
    get new_admin_location_path
    assert_redirected_to edit_admin_business_path
  end

  test "adding a location with its team shows the Locations tab" do
    tech = member_with_role(:technician)
    member = @business.business_users.find_by(user: tech)
    post admin_locations_path, params: { location: { name: "North yard", phone: "555-0111", city: "Yonkers", timezone: "America/Chicago", member_ids: [ "", member.uid ] } }
    assert_redirected_to admin_locations_path
    location = as_business(@business) { Location.find_by!(name: "North yard") }
    assert_equal "America/Chicago", location.timezone
    assert_equal [ tech ], as_business(@business) { location.members.to_a }
    follow_redirect!
    assert_select "nav.tabs a[aria-current=page]", "Locations"
    assert_select "#location-#{location.uid}", /North yard.*555-0111.*#{tech.full_name}/m

    patch admin_location_path(location), params: { location: { name: "North", member_ids: [ "" ] } }
    assert_redirected_to admin_locations_path
    assert_equal "North", location.reload.name
    assert_empty as_business(@business) { location.members.reload.to_a }
  end

  test "the main location's form only names it" do
    branch
    main = @business.primary_location
    get edit_admin_location_path(main)
    assert_select "input[name='location[phone]']", 0
    patch admin_location_path(main), params: { location: { name: "Head office", phone: "555-9999" } }
    assert_equal [ "Head office", nil ], [ main.reload.name, main.phone ]
  end

  test "each location's hours and closures are edited on the Hours tab" do
    location = branch
    get admin_hours_path(location:)
    assert_select "nav[aria-label=Location] a[aria-current=page]", "North yard"
    patch admin_hours_path(location:), params: { preset: "weekdays" }
    assert_redirected_to admin_hours_path(location:)
    assert_equal WeeklyHours::WEEKDAYS_8_TO_5, location.reload.weekly_hours
    assert_nil @business.reload.weekly_hours, "the main location's hours are untouched"

    post admin_closures_path(location:), params: { closure: { reason: "Yard move", starts_on: "2026-12-01" } }
    assert_redirected_to admin_hours_path(location:)
    closure = as_business(@business) { Closure.find_by!(reason: "Yard move") }
    assert_equal location.id, closure.location_id
    get admin_hours_path
    assert_select "#closure-#{closure.uid}", 0
  end

  test "archiving, restoring, and the plan gate on downgrade" do
    location = branch
    patch archive_admin_location_path(location)
    assert location.reload.archived?
    patch archive_admin_location_path(@business.primary_location)
    assert_match "can't be archived", flash[:alert]
    @business.update!(plan_overrides: {})
    patch restore_admin_location_path(location)
    assert_match "isn't included in your plan", flash[:alert]
    get admin_locations_path
    assert_response :success, "existing locations stay readable"
    post admin_locations_path, params: { location: { name: "South" } }
    assert_response :unprocessable_content
  end

  test "a new location's time zone follows the business until one is chosen" do
    post admin_locations_path, params: { location: { name: "North yard", timezone: "" } }
    location = as_business(@business) { Location.find_by!(name: "North yard") }
    assert_nil location.timezone
    @business.update!(timezone: "America/Chicago")
    assert_equal "America/Chicago", as_business(@business) { location.reload.time_zone.tzinfo.identifier }
  end

  test "deactivated members aren't listed as working at a location" do
    tech = member_with_role(:technician)
    location = branch
    as_business(@business) { LocationMember.create!(location:, user: tech) }
    @business.business_users.find_by(user: tech).deactivate!
    get admin_locations_path
    assert_select "#location-#{location.uid}", /Nobody assigned/
  end

  test "a member's default location" do
    location = branch
    member = business_users(:one)
    patch member_default_admin_locations_path(member: member.uid), params: { default_location: location.uid }
    assert_equal location, as_business(@business) { member.reload.default_location }
    patch member_default_admin_locations_path(member: member.uid), params: { default_location: "" }
    assert_nil member.reload.default_location
  end

  test "automations can be limited to a location once there are several (NTF-04)" do
    @business.update!(plan_overrides: { "features" => { "locations" => true, "automations" => true }, "limits" => { "active_automations" => 5 } })
    get new_admin_automation_path
    assert_select "select#condition-location", 0
    location = branch
    get new_admin_automation_path
    assert_select "select#condition-location option", [ "Any location", @business.primary_location.name, "North yard" ].size
    post admin_automations_path, params: { automation_rule: { name: "North notice", trigger: "quote_sent", delay_amount: "0", delay_unit: "hours",
                                                              conditions: { location: location.uid }, actions: { notify_team: { on: "1", team: "office" } } } }
    follow_redirect!
    assert_select "#automation-#{as_business(@business) { AutomationRule.last.uid }} p", /if it's for North yard:/
    rule = as_business(@business) { AutomationRule.last }
    patch archive_admin_location_path(location)
    get edit_admin_automation_path(rule)
    assert_select "select#condition-location option[selected]", "North yard (archived)", "an archived location stays on the rule"
  end

  test "another business's locations aren't found" do
    theirs = branch(business: businesses(:two).tap { _1.update!(plan_overrides: { "features" => { "locations" => true } }) })
    assert_not_found_across_businesses { get edit_admin_location_path(theirs) }
    assert_not_found_across_businesses { patch admin_location_path(theirs), params: { location: { name: "Mine" } } }
    assert_not_found_across_businesses { patch restore_admin_location_path(theirs) }
    assert_not_found_across_businesses { get new_admin_closure_path(location: theirs) }
    assert_not_found_across_businesses { post admin_closures_path(location: theirs), params: { closure: { reason: "Off", starts_on: "2026-12-01" } } }
    assert_equal "North yard", as_business(businesses(:two)) { theirs.reload.name }
    assert_not_found_across_businesses { patch archive_admin_location_path(theirs) }
    assert_not_found_across_businesses { get admin_hours_path(location: theirs) }
    assert_not_found_across_businesses { patch member_default_admin_locations_path(member: business_users(:two).uid), params: { default_location: "" } }
  end
end
