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
end
