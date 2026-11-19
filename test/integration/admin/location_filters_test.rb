require "test_helper"

# CAT-07: lists, the calendar and the dashboard filtered by location, remembered per member.
class Admin::LocationFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    @main = @business.primary_location
    as_business(@business) do
      @north = Location.create!(name: "North yard", timezone: "America/Chicago", weekly_hours: { "1" => { "opens" => "10:00", "closes" => "12:00" } })
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "1 Elm St", billing: true } ])
      @here = Quote.start(client: @maria, location: @main).tap { _1.update!(title: "Main quote") }
      @there = Quote.start(client: @maria, location: @north).tap { _1.update!(title: "North quote") }
      Job.create!(client: @maria, property: @maria.properties.first, title: "Main job", location: @main)
      Job.create!(client: @maria, property: @maria.properties.first, title: "North job", location: @north)
      ServiceRequest.create!(client: @maria, source: "phone", description: "North request", location: @north)
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def member = business_users(:one).reload

  test "lists show every location until one is chosen, and the choice is remembered" do
    get admin_quotes_path
    assert_select "select#location-filter option[selected]", "All locations"
    assert_select "body", /Main quote.*North quote|North quote.*Main quote/m

    get admin_quotes_path(location: @north.uid)
    assert_equal @north.uid, member.location_filter
    assert_select "select#location-filter option[selected]", "North yard"
    assert_select "body", text: /Main quote/, count: 0
    assert_match "North quote", response.body

    post search_admin_quotes_path, params: { q: "" }
    assert_no_match "Main quote", response.body, "searches keep the filter"
    get admin_jobs_path
    assert_match "North job", response.body
    assert_no_match "Main job", response.body
    get admin_service_requests_path(status: "new")
    assert_match "North request", response.body

    get admin_jobs_path(location: "all")
    assert_match "Main job", response.body
    assert_equal "all", member.location_filter
  end

  test "a member's default location is their starting filter" do
    business_users(:one).update!(default_location: @north)
    get admin_jobs_path
    assert_no_match "Main job", response.body
  end

  test "the calendar and dashboard follow the filter, with the location's hours and time zone" do
    get admin_root_path(location: @north.uid)
    assert_select ".page-lede", /North yard stands/
    get admin_schedule_path(view: "day", date: "2026-11-23")
    assert_select "select#location-filter option[selected]", "North yard"
    monday = Date.new(2026, 11, 23)
    north = as_business(@business) { ScheduleView.new(@business, view: "day", date: monday, location: @north).then { [ _1.hours, _1.shades_on(monday).size ] } }
    assert_equal [ 10...12, 0 ], north, "North yard's Monday, 10 to noon, fills the grid"
    main = as_business(@business) { ScheduleView.new(@business, view: "day", date: monday).hours }
    assert_equal ScheduleView::DEFAULT_HOURS.first...ScheduleView::DEFAULT_HOURS.last, main, "the main location has no hours set"
  end

  test "no filter with one location, and another business's location is ignored" do
    theirs = businesses(:two).primary_location
    get admin_quotes_path(location: theirs.uid)
    assert_nil member.location_filter
    assert_match "Main quote", response.body

    as_business(@business) { [ @there, Job.find_by!(title: "North job"), ServiceRequest.last ].each(&:destroy!); @north.destroy! }
    get admin_quotes_path
    assert_select "select#location-filter", 0
  end
end
