require "test_helper"

# CLI-07: the inbox shows who has each request and when, filters by who has it, and marks
# follow-ups whose day has passed.
class Admin::RequestInboxFollowUpsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    @marcus = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @marcus, business: @business, role: "admin")
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      sam = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5550100101" } ])
      ana = Client.create!(display_name: "Ana Diaz", contact_methods_attributes: [ { kind: "phone", value: "5550100102" } ])
      @mine = ServiceRequest.create!(client: maria, source: "phone", description: "Fence")
      @theirs = ServiceRequest.create!(client: sam, source: "phone", description: "Gutters")
      @nobodys = ServiceRequest.create!(client: ana, source: "phone", description: "Hedges")
      RequestFollowUp.assign!(@mine, { user: @owner, scheduled_on: Date.new(2026, 11, 20) }, by: @owner)
      RequestFollowUp.assign!(@theirs, { user: @marcus, kind: "call", scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "14:00" }, by: @owner)
      @nobodys.move_to!("in_progress")
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "each request shows who has it and when, and an overdue one says so" do
    get admin_service_requests_path(status: "in_progress")
    assert_select "#request-#{@mine.uid}", /John Doe · Site visit, Fri, Nov 20 · Anytime\s*Overdue/
    assert_select "#request-#{@theirs.uid}", /Marcus Reyes · Call, Tue, Nov 24 · 2 pm/
    assert_select "#request-#{@theirs.uid} .badge", { text: "Overdue", count: 0 }
    assert_select "#request-#{@nobodys.uid}", /Not assigned/
  end

  test "filtering by who has it: me, nobody, or one person, kept across the status tabs" do
    names = -> { css_select("ul.list li").map { _1["id"].delete_prefix("request-") } }
    get admin_service_requests_path(status: "in_progress", assignee: "mine")
    assert_equal [ @mine.uid ], names.()
    assert_select "nav.tabs a[href=?]", admin_service_requests_path(status: "new", assignee: "mine")
    assert_select "nav.tabs a[aria-current=page]", /In progress\s*1/
    get admin_service_requests_path(status: "in_progress", assignee: "unassigned")
    assert_equal [ @nobodys.uid ], names.()
    get admin_service_requests_path(status: "in_progress", assignee: @marcus.id)
    assert_equal [ @theirs.uid ], names.()
    assert_select "select#assignee-filter option[selected]", "Assigned to Marcus Reyes"
    get admin_service_requests_path(status: "in_progress", assignee: "nonsense")
    assert_equal 3, names.().size, "an unknown filter shows everyone's"
  end

  test "only this business's people can be filtered by; your own id is \"Assigned to me\"; nobody's is for open requests" do
    other = User.create!(email: "olga@example.com", password: "password123", first_name: "Olga", last_name: "Other", confirmed_at: Time.current)
    BusinessUser.create!(user: other, business: businesses(:two), role: "admin")
    get admin_service_requests_path(status: "in_progress", assignee: other.id)
    assert_select "ul.list li", 3, "not a filter here, so everyone's"
    assert_select "select#assignee-filter option[selected]", 0
    assert_no_match "Olga", response.body

    get admin_service_requests_path(status: "in_progress", assignee: @owner.id)
    assert_select "select#assignee-filter option[selected]", "Assigned to me"
    tech = User.create!(email: "tia@example.com", password: "password123", first_name: "Tia", confirmed_at: Time.current)
    BusinessUser.create!(user: tech, business: @business, role: "technician")
    get admin_service_requests_path
    assert_select "select#assignee-filter option", /Tia/, "JOB-06: technicians can be given requests"

    as_business(@business) { @nobodys.move_to!("archived") }
    get admin_service_requests_path(status: "archived", assignee: "unassigned")
    assert_select "ul.list li", 0
    assert_select "nav.tabs a", /Archived\s*0/
    get admin_service_requests_path(status: "new", assignee: "mine")
    assert_select ".empty-title", "Nothing here"
  end

  test "overdue goes by the request location's own clock" do
    travel_to Time.utc(2026, 11, 23, 5, 30) # 00:30 Monday in New York; 7:30 pm Sunday in Honolulu
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    as_business(@business) do
      honolulu = Location.create!(name: "Island yard", timezone: "Pacific/Honolulu")
      @theirs.update!(location: honolulu)
      @theirs.follow_up.update!(scheduled_on: Date.new(2026, 11, 22), timing: "anytime")
      @mine.follow_up.update!(scheduled_on: Date.new(2026, 11, 22))
    end
    get admin_service_requests_path(status: "in_progress", location: "all")
    assert_select "#request-#{@mine.uid} .badge", "Overdue"
    assert_select "#request-#{@theirs.uid} .badge", { text: "Overdue", count: 0 }, "still Sunday there"
  end

  test "a page of rows doesn't look up the business or count locations per row" do
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    as_business(@business) do
      Location.create!(name: "Island yard", timezone: "Pacific/Honolulu")
      client = Client.create!(display_name: "Many", contact_methods_attributes: [ { kind: "phone", value: "5550100109" } ])
      20.times { RequestFollowUp.assign!(ServiceRequest.create!(client:, source: "phone", description: "More"), { user: @marcus, scheduled_on: Date.new(2026, 11, 24) }, by: @owner) }
    end
    queries = 0
    callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" } # cached ones too: each is still work
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_service_requests_path(status: "in_progress") }
    assert_select "ul.list li", 23
    assert_operator queries, :<, 40, "not one business and location count per row (68 before)"
  end
end
