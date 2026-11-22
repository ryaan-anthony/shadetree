require "test_helper"

# JOB-08: people who schedule but can't see requests see others' follow-ups as Busy: the time and
# the person, nothing of the request, not even in the page's source.
class Admin::ScheduleBusyTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 14) # Monday, 9 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5,
                      plan_overrides: { "features" => { "custom_roles" => true, "locations" => true }, "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "technician")
    @monday = Date.new(2026, 11, 23)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
      @one_pm = Job.create!(client: maria, title: "Spring cleanup").visits.new(scheduled_on: @monday, timing: "exact", start_time: "13:00", duration_minutes: 60, assignee_ids: [ @tech.id ])
                   .tap { _1.schedule!(by: @owner) }
      sam = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5125550101" } ])
      ana = Client.create!(display_name: "Ana Diaz", contact_methods_attributes: [ { kind: "phone", value: "5125550102" } ])
      @site = ServiceRequest.create!(client: sam, source: "phone", description: "Fence")
      RequestFollowUp.assign!(@site, { user: @tech, scheduled_on: @monday, timing: "exact", start_time: "14:00", instructions: "Gate code 4411" }, by: @owner)
      @call = ServiceRequest.create!(client: ana, source: "phone", description: "Hedges")
      RequestFollowUp.assign!(@call, { user: @owner, kind: "call", scheduled_on: @monday + 1 }, by: @owner)
      @dispatcher = Role.create!(name: "Dispatcher", permissions: %w[schedule])
    end
    @dee = User.create!(email: "dee@example.com", password: "password123", first_name: "Dee", last_name: "Park", confirmed_at: Time.current)
    BusinessUser.create!(user: @dee, business: @business, role: "custom", role_id: @dispatcher.id)
    sign_in_as @dee
  end

  def sign_in_as(user)
    sign_in user
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def week(**params) = get(admin_schedule_path(date: @monday.iso8601, **params))
  def follow_ups = as_business(@business) { RequestFollowUp.where(service_request: [ @site, @call ]).to_a }

  # Nothing of either request anywhere in the page's source: names, what was asked, instructions,
  # ids, the follow-up's styling or kind, or its done state.
  def assert_nothing_of_the_requests
    body = response.body
    [ "Sam Ortiz", "Ana Diaz", "Fence", "Hedges", "Gate code", "cal-request", "cal-call", "for a request", "/requests/", "follow-ups/",
      @site.uid, @call.uid, *follow_ups.map(&:uid) ].each { assert_not_includes body, _1 }
    calendar = css_select("#schedule-grid, #schedule-agenda").map(&:text).join
    [ /site visit/i, /\bcall\b/i, /\bdone\b/i ].each { assert_no_match _1, calendar }
    # A Busy block, and everything in it, carries only its look: no id, data, link, title or label.
    css_select(".cal-busy, .cal-busy *").each { assert_empty _1.attributes.keys - %w[class aria-hidden], _1.to_html }
  end

  test "others' follow-ups are Busy at their time on their person's day, or in the anytime row, and say nothing more" do
    week
    assert_select "#schedule-grid .cal-busy.cal-#{as_business(@business) { ScheduleView.new(@business).color_for(@tech) }}", 1
    assert_select "#schedule-grid .cal-busy .sr-only", "Busy, 2 to 3 pm, Marcus"
    assert_select "#schedule-grid [data-kind=anytime] .cal-busy .sr-only", "Busy, anytime, John"
    assert_select "#schedule-grid .cal-busy", /2 pm\s*Busy\s*Marcus/
    assert_select "#schedule-grid a.cal-busy, #schedule-grid .cal-busy a, .cal-busy[tabindex], .cal-busy[data-schedule-drag-target]", 0, "not a link, drag handle or control"
    assert_select "#cal-visit-#{@one_pm.uid}", /Maria Lopez/, "visits as before"
    assert_nothing_of_the_requests

    get admin_schedule_path(date: @monday.iso8601, view: "day")
    assert_select "[data-kind=timed][data-member='#{@tech.id}'] .cal-busy .sr-only", "Busy, 2 to 3 pm, Marcus"
    assert_nothing_of_the_requests
  end

  test "a window says when they're arriving; times are on the calendar's clock, its zone named when the request's differs" do
    as_business(@business) { RequestFollowUp.assign!(@site, { timing: "window", start_time: "14:00", window_end_time: "16:00" }, by: @owner) }
    week
    assert_select "#schedule-grid .cal-busy .sr-only", "Busy, arriving 2 to 4 pm, Marcus"
    assert_select "#schedule-grid .cal-busy", /2–4 pm\s*Busy/

    north = as_business(@business) { Location.create!(name: "North yard", timezone: "America/Chicago") }
    as_business(@business) { @site.update!(location: north) }
    week
    assert_select "#schedule-grid .cal-busy .sr-only", "Busy, arriving 1 to 3 pm CST, Marcus", "its own clock, zone named, as JOB-07 does"
  end

  test "done ones are Busy too; by status they're neutral; the filters and the phone agenda include them" do
    as_business(@business) { @site.follow_up.done!(by: @tech) }
    week(color: "status")
    assert_select "#schedule-grid .cal-busy.cal-neutral", 2
    assert_select ".cal-busy[class*=cal-status]", 0
    assert_nothing_of_the_requests

    week
    assert_select "#schedule-agenda li", /2 pm\s*Busy · Marcus/
    assert_select "#schedule-agenda li a", { text: /Busy/, count: 0 }, "not a link"
    week(member: @tech.id)
    assert_select "#schedule-grid .cal-busy", 1
    week(member: "unassigned")
    assert_select ".cal-busy", 0
    north = as_business(@business) { Location.create!(name: "North yard") }
    as_business(@business) { @call.update!(location: north) }
    week(location: north.uid)
    assert_select "#schedule-grid .cal-busy .sr-only", "Busy, anytime, John"
    assert_nothing_of_the_requests
  end

  test "the folded earlier days count Busy, without detail" do
    travel_to Time.utc(2026, 11, 25, 14) # Wednesday
    week
    assert_select "#schedule-earlier summary", "Earlier this week (1 visit, 2 busy)"
    assert_select "#schedule-earlier li", "Mon 2 pm · Busy · Marcus"
    assert_select "#schedule-earlier li a", { text: /Busy/, count: 0 }
    assert_nothing_of_the_requests
  end

  test "booked hours count Busy time, matching the office's" do
    week
    assert_select "#schedule-members li", /Marcus Reyes\s*2 h/
    sign_in_as @owner
    week
    assert_select "#schedule-members li", /Marcus Reyes\s*2 h/
  end

  test "Busy time takes no drops or slot clicks: a visit can be booked over it, with the follow-up warning that names nobody" do
    get admin_schedule_path(date: @monday.iso8601, view: "day")
    assert_select "[data-kind=timed][data-member='#{@tech.id}'] a.cal-slot[href*='at=14%3A00']", 1, "the 2 pm hour is still a slot"
    patch admin_schedule_move_path(@one_pm), params: { lock_version: @one_pm.lock_version, on: "2026-11-23", at: "14:00" }, as: :json
    assert_equal [ "Marcus Reyes has a request follow-up then (2 pm)." ], response.parsed_body["warnings"]
    patch admin_schedule_move_path(@one_pm), params: { lock_version: @one_pm.lock_version, on: "2026-11-23", at: "14:00", confirm: response.parsed_body["confirm"] }, as: :json
    assert_response :success
    assert_equal "2 pm", as_business(@business) { @one_pm.reload.time_label }
  end

  test "opening, moving, reassigning or unassigning a follow-up stays refused; a slot offers only a visit" do
    follow_up = follow_ups.first
    get admin_schedule_follow_up_path(@site)
    assert_response :forbidden
    patch admin_schedule_follow_up_move_path(@site), params: { lock_version: follow_up.lock_version, on: "2026-11-24", at: "10:00" }, as: :json
    assert_response :forbidden
    get edit_admin_service_request_follow_up_path(@site)
    assert_response :forbidden
    delete admin_service_request_follow_up_path(@site), params: { lock_version: follow_up.lock_version }
    assert_response :forbidden
    assert_equal [ @monday, @tech.id ], as_business(@business) { @site.reload.follow_up.then { [ _1.scheduled_on, _1.user_id ] } }
    get admin_schedule_new_visit_path(on: "2026-11-25", at: "10:00")
    assert_select "#new-follow-up", 0
  end

  test "their own follow-ups show the kind and client, as on My day, and open there" do
    as_business(@business) { @dispatcher.update!(permissions: %w[schedule field_work]) }
    as_business(@business) { RequestFollowUp.assign!(@call, { user: @dee, kind: "call", scheduled_on: @monday + 1 }, by: @owner) }
    week
    assert_select "#schedule-grid a.cal-request.cal-call[href=?]", admin_my_request_path(@call), /Ana Diaz.*Call for a request/m
    assert_select "#schedule-grid a.cal-request[data-move-url]", 0, "moved by the office, not from here"
    assert_select "#schedule-grid .cal-busy .sr-only", "Busy, 2 to 3 pm, Marcus"
    assert_not_includes response.body, @site.uid
    assert_not_includes response.body, "Sam Ortiz"
  end

  test "an empty week's hint counts Busy, with no detail" do
    as_business(@business) { Visit.where(id: @one_pm.id).update_all(status: "cancelled") }
    get admin_schedule_path(date: (@monday - 7).iso8601)
    assert_select "#next-visit a", /Next: Busy, Mon/
    assert_nothing_of_the_requests
  end

  test "office staff see follow-ups as before, not Busy" do
    sign_in_as @owner
    week
    assert_select ".cal-busy", 0
    assert_select "#cal-request-#{@site.uid}", /Sam Ortiz/
  end

  test "another business's follow-ups aren't shown as Busy, and its requests aren't found" do
    other = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Other Client", contact_methods_attributes: [ { kind: "phone", value: "5125550109" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Elsewhere").tap do
        RequestFollowUp.assign!(_1, { user: users(:two), scheduled_on: @monday, timing: "exact", start_time: "09:00" }, by: users(:two))
      end
    end
    week
    assert_select "#schedule-grid .cal-busy", 2
    assert_not_includes response.body, other.uid
    as_business(@business) { @dispatcher.update!(permissions: %w[schedule field_work]) }
    assert_not_found_across_businesses { get admin_my_request_path(other) }
  end
end
