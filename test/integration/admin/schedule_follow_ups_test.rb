require "test_helper"

# JOB-07: request follow-ups on the team calendar: where they sit, how they look, the person
# filter, colors, the phone agenda, and who sees them.
class Admin::ScheduleFollowUpsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 14) # Monday, 9 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "technician")
    @monday = Date.new(2026, 11, 23)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
      job = Job.create!(client: maria, title: "Spring cleanup")
      @one_pm = job.visits.new(scheduled_on: @monday, timing: "exact", start_time: "13:00", duration_minutes: 60, assignee_ids: [ @tech.id ]).tap { _1.schedule!(by: @owner) }
      sam = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5125550101" } ])
      ana = Client.create!(display_name: "Ana Diaz", contact_methods_attributes: [ { kind: "phone", value: "5125550102" } ])
      @site = ServiceRequest.create!(client: sam, source: "phone", description: "Fence")
      RequestFollowUp.assign!(@site, { user: @tech, scheduled_on: @monday, timing: "exact", start_time: "14:00" }, by: @owner)
      @call = ServiceRequest.create!(client: ana, source: "phone", description: "Hedges")
      RequestFollowUp.assign!(@call, { user: @owner, kind: "call", scheduled_on: @monday + 1 }, by: @owner)
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def week(**params) = get(admin_schedule_path(date: @monday.iso8601, **params))

  test "the week shows follow-ups at their time or with the anytime ones, dashed, a call lighter, labelled, with the client" do
    week
    assert_select "#schedule-grid a#cal-request-#{@site.uid}.cal-visit.cal-request:not(.cal-call)", /2 pm Sam Ortiz.*Site visit for a request.*Marcus/m
    assert_select "#schedule-grid a#cal-request-#{@call.uid}.cal-chip.cal-request.cal-call", /Ana Diaz.*Call for a request.*John/m
    assert_select "#schedule-grid a#cal-visit-#{@one_pm.uid}.cal-visit:not(.cal-request)"
    assert_select "#schedule-members li", /Marcus Reyes\s*2 h/, "the visit and the follow-up"
  end

  test "the day split by person puts a follow-up in its person's column; the person filter and status colors include them" do
    get admin_schedule_path(date: @monday.iso8601, view: "day")
    assert_select "#cal-request-#{@site.uid}-#{@tech.id}"
    week(member: @tech.id)
    assert_select "#cal-request-#{@site.uid}"
    assert_select "#cal-request-#{@call.uid}", 0, "someone else's"
    week(member: "unassigned")
    assert_select "[id^=cal-request-]", 0, "a follow-up always has someone"

    as_business(@business) { @site.follow_up.done!(by: @tech) }
    week(color: "status")
    assert_select "#cal-request-#{@site.uid}.cal-status-completed", /done/
    assert_select "#cal-request-#{@call.uid}.cal-status-scheduled"
  end

  test "the phone agenda lists them too" do
    week
    assert_select "#schedule-agenda li", /2 pm.*Sam Ortiz.*Site visit for a request · Marcus/m
    assert_select "#schedule-agenda li", /Anytime.*Ana Diaz.*Call for a request/m
  end

  test "only people who can see requests see them; at a location, only that location's" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true, "locations" => true }, "limits" => { "team_members" => nil } })
    dispatcher = as_business(@business) { Role.create!(name: "Dispatcher", permissions: %w[schedule]) }
    dee = User.create!(email: "dee@example.com", password: "password123", first_name: "Dee", confirmed_at: Time.current)
    BusinessUser.create!(user: dee, business: @business, role: "custom", role_id: dispatcher.id)
    sign_in dee
    post switch_admin_business_path, params: { business: @business.uid }
    week
    assert_response :success
    assert_select "[id^=cal-request-]", 0
    assert_select "#cal-visit-#{@one_pm.uid}"

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    north = as_business(@business) { Location.create!(name: "North yard") }
    as_business(@business) { @call.update!(location: north) }
    week(location: north.uid)
    assert_select "#cal-request-#{@call.uid}"
    assert_select "#cal-request-#{@site.uid}", 0
  end

  test "a week of visits and follow-ups doesn't query per item" do
    count = lambda do # on a fresh sign-in each time, so both counts are taken the same way
      sign_out @owner
      sign_in @owner
      post switch_admin_business_path, params: { business: @business.uid }
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { week }
      queries
    end
    before = count.()
    as_business(@business) do
      client = Client.create!(display_name: "Busy", contact_methods_attributes: [ { kind: "phone", value: "5125550199" } ])
      10.times { |n| RequestFollowUp.assign!(ServiceRequest.create!(client:, source: "phone", description: "More #{n}"), { user: @tech, scheduled_on: @monday + (n % 5), timing: "exact", start_time: "10:00" }, by: @owner) }
    end
    assert_equal before, count.()
  end

  def move(request = @site, **params)
    follow_up = as_business(@business) { request.reload.follow_up }
    patch admin_schedule_follow_up_move_path(request), params: { lock_version: follow_up.lock_version, **params }, as: :json
  end

  def follow_up(request = @site) = as_business(@business) { request.reload.follow_up }

  test "opening one shows the request in brief with Open request, Move, Reassign and Unassign; only for people who manage requests" do
    get admin_schedule_follow_up_path(@site)
    assert_select "h2", "Sam Ortiz"
    assert_select "a[href=?]", admin_service_request_path(@site), "Open request"
    assert_select "button", "Move"
    assert_select "a[href=?]", edit_admin_service_request_follow_up_path(@site), "Reassign"
    assert_select "form[action=?] button", admin_service_request_follow_up_path(@site), "Unassign"
    week
    assert_select "#cal-request-#{@site.uid}[data-move-url=?]", admin_schedule_follow_up_move_path(@site)

    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_schedule_follow_up_path(@site) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { move(on: "2026-11-24", at: "10:00") }
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get admin_schedule_follow_up_path(@site) }
    assert_not_found_across_businesses { patch admin_schedule_follow_up_move_path(@site), params: { on: "2026-11-24" } }
  end

  test "dragging to another time, day or person moves it, tells the people concerned and offers Undo" do
    move(on: "2026-11-24", at: "10:00")
    assert_response :success
    assert_equal [ Date.new(2026, 11, 24), "10 am", @tech ], [ follow_up.scheduled_on, follow_up.time_label, follow_up.user ]
    assert_match "Moved: Site visit for Sam Ortiz, Tue, Nov 24 · 10 am · Marcus Reyes.", flash[:notice]
    undo = flash[:undo]
    assert_equal [ "Moved: site visit for Sam Ortiz is now Tue, Nov 24 · 10 am" ], as_business(@business) { Notification.where(user: @tech, kind: "request_changed").pluck(:title) }

    patch undo["path"], params: undo["params"]
    assert_redirected_to %r{/admin/schedule}
    assert_equal [ @monday, "2 pm" ], [ follow_up.scheduled_on, follow_up.time_label ]
    assert_match "Put back", flash[:notice]

    move(on: "2026-11-23", at: "14:00", from: @tech.id, to: @owner.id)
    assert_equal @owner, follow_up.user
    assert_equal "reassigned", as_business(@business) { @site.events.where(kind: "reassigned").last&.kind }
  end

  test "the same warnings as visits come first; Move anyway goes ahead; a stale or impossible move is refused" do
    move(on: "2026-11-23", at: "13:30")
    assert_response :unprocessable_content
    body = response.parsed_body
    assert_equal [ "Marcus Reyes is on #{as_business(@business) { @one_pm.job.number }} Spring cleanup then (1 pm)." ], body["warnings"]
    move(on: "2026-11-23", at: "13:30", confirm: body["confirm"])
    assert_response :success
    assert_equal "1:30 pm", follow_up.time_label

    patch admin_schedule_follow_up_move_path(@site), params: { lock_version: 0, on: "2026-11-25" }, as: :json
    assert_response :conflict
    move(on: "2026-11-25", to: "none", from: @tech.id)
    assert_match "Use Unassign instead", response.parsed_body["error"]
    move(on: "2026-11-25", to: users(:two).id, from: @tech.id)
    assert_match "isn't on your team", response.parsed_body["error"]
    assert_equal @monday, follow_up.scheduled_on
  end

  test "the quick-edit sheet moves it without a mouse, and warnings come back in it" do
    patch admin_schedule_follow_up_move_path(@site), params: { lock_version: follow_up.lock_version, on: "2026-11-23", at: "13:30", to: @tech.id }
    assert_response :unprocessable_content
    assert_select ".banner-warning li", /is on/
    assert_select "input[type=submit][value='Move anyway']"
    patch admin_schedule_follow_up_move_path(@site), params: { lock_version: follow_up.lock_version, on: "2026-11-25", at: "09:00", to: @owner.id }
    assert_redirected_to admin_schedule_path(date: "2026-11-25", focus: @site.uid)
    assert_equal [ "9 am", @owner ], [ follow_up.time_label, follow_up.user ]
  end

  test "unassigning from the calendar goes back to it; a done follow-up can't be dragged" do
    delete admin_service_request_follow_up_path(@site), params: { lock_version: follow_up.lock_version, from: "schedule" }
    assert_redirected_to admin_schedule_path, "with nothing more to keep"
    assert_nil follow_up
    as_business(@business) { @call.follow_up.done!(by: @owner) }
    week
    assert_select "#cal-request-#{@call.uid}[data-move-url]", 0
  end

  test "booked hours follow the location filter, and leave follow-ups out for someone who can't see requests" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true, "locations" => true }, "limits" => { "team_members" => nil } })
    north = as_business(@business) { Location.create!(name: "North yard") }
    week(location: north.uid)
    assert_select "#schedule-members li", /Marcus Reyes\s*0 h/, "nothing of his at North yard yet"
    as_business(@business) { @site.update!(location: north) }
    week(location: north.uid)
    assert_select "#schedule-members li", /Marcus Reyes\s*1 h/, "the follow-up, now at North yard"
    week(location: "all")
    assert_select "#schedule-members li", /Marcus Reyes\s*2 h/

    dispatcher = as_business(@business) { Role.create!(name: "Dispatcher", permissions: %w[schedule]) }
    dee = User.create!(email: "dee@example.com", password: "password123", first_name: "Dee", confirmed_at: Time.current)
    BusinessUser.create!(user: dee, business: @business, role: "custom", role_id: dispatcher.id)
    sign_in dee
    post switch_admin_business_path, params: { business: @business.uid }
    week(location: "all")
    assert_select "#schedule-members li", /Marcus Reyes\s*1 h/
  end

  test "someone who can't see requests is told a person has a request follow-up, not whose" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    dispatcher = as_business(@business) { Role.create!(name: "Dispatcher", permissions: %w[schedule]) }
    dee = User.create!(email: "dee@example.com", password: "password123", first_name: "Dee", confirmed_at: Time.current)
    BusinessUser.create!(user: dee, business: @business, role: "custom", role_id: dispatcher.id)
    sign_in dee
    post switch_admin_business_path, params: { business: @business.uid }
    patch admin_schedule_move_path(@one_pm), params: { lock_version: @one_pm.lock_version, on: "2026-11-23", at: "14:00" }, as: :json
    assert_equal [ "Marcus Reyes has a request follow-up then (2 pm)." ], response.parsed_body["warnings"]
  end

  test "a done follow-up has no Move, and can't be moved" do
    as_business(@business) { @site.follow_up.done!(by: @tech) }
    get admin_schedule_follow_up_path(@site)
    assert_select "button", { text: "Move", count: 0 }
    move(on: "2026-11-25", at: "10:00")
    assert_match "is done", response.parsed_body["error"]
    assert follow_up.done?
  end

  test "a window keeps its length when moved; a drag on another zone's grid lands at the same moment on the request's clock" do
    as_business(@business) { RequestFollowUp.assign!(@site, { timing: "window", start_time: "14:00", window_end_time: "16:00" }, by: @owner) }
    move(on: "2026-11-24", at: "09:00")
    assert_equal "Arrive 9–11 am", follow_up.time_label
    move(on: "2026-11-24", at: "09:00", grid_zone: "America/Chicago")
    assert_equal "Arrive 10 am–12 pm", follow_up.time_label, "9 am in Chicago is 10 am in New York"
  end

  test "unassigning from the calendar comes back to the same day, view and person" do
    delete admin_service_request_follow_up_path(@site), params: { lock_version: follow_up.lock_version, from: "schedule", date: "2026-11-23", view: "day", member: @tech.id }
    assert_redirected_to admin_schedule_path(date: "2026-11-23", view: "day", member: @tech.id)
  end
end
