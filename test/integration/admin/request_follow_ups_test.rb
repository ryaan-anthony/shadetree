require "test_helper"

# CLI-07: assigning requests from the request page and when logging one; moving, handing on and
# unassigning; warnings; who may do it.
class Admin::RequestFollowUpsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @marcus = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @marcus, business: @business, role: "admin")
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @request_record = ServiceRequest.create!(client: @maria, source: "phone", description: "Fence repair")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def assign(fresh: nil, **fields)
    patch admin_service_request_follow_up_path(@request_record),
          params: { fresh:, request_follow_up: { user_id: @marcus.id, kind: "visit", scheduled_on: "2026-11-24", timing: "exact", start_time: "14:00", window_end_time: "",
                                         duration_hours: "", instructions: "Check the back gate" }.merge(fields) }
  end

  def follow_up = as_business(@business) { @request_record.reload.follow_up }

  test "only people who manage requests assign them; other businesses' requests and members, and suspended businesses, are refused" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_service_request_follow_up_path(@request_record) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { assign }
    assert_permission_matrix(owner: true, admin: true, technician: false) { delete admin_service_request_follow_up_path(@request_record) }

    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get edit_admin_service_request_follow_up_path(@request_record) }
    assert_not_found_across_businesses { assign }
    assert_not_found_across_businesses { delete admin_service_request_follow_up_path(@request_record) }

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    assign(user_id: users(:two).id)
    assert_response :unprocessable_content, "someone in another business can't be given it"
    assert_select ".error-text", "Choose who follows it up."
    assert_nil follow_up

    @business.update_columns(suspended_at: Time.current)
    assign
    assert_response :forbidden
    assert_nil follow_up
  end

  test "assigning from the request page, then moving it, handing it on and unassigning it" do
    get admin_service_request_path(@request_record)
    assert_select "#follow-up", /Nobody's following this up/
    get edit_admin_service_request_follow_up_path(@request_record)
    assert_select "input#follow-up-kind-visit[checked]"
    assert_select "input#timing-anytime[checked]"
    assert_select "input[name='request_follow_up[scheduled_on]'][value='2026-11-23']", 1, "today by default"
    assert_select "select[name='request_follow_up[user_id]'] option", /Marcus Reyes \(Admin\)/
    tech = member_with_role(:technician)
    assert_select "select[name='request_follow_up[user_id]'] option[value=?]", tech.id.to_s, false, "not until JOB-06 shows follow-ups on My day"
    assert_select "input[name=fresh][value='1']"

    assign
    assert_redirected_to admin_service_request_path(@request_record)
    assert_equal "Marcus Reyes has it: site visit, Tue, Nov 24 · 2 pm.", flash[:notice]
    assert_equal [ @marcus, "2 pm", 60, "Check the back gate" ], [ follow_up.user, follow_up.time_label, follow_up.duration_minutes, follow_up.instructions ]
    assert_equal "in_progress", as_business(@business) { @request_record.reload.status }
    follow_redirect!
    assert_select "#follow-up", /Marcus Reyes.*Site visit, Tue, Nov 24 · 2 pm.*About 1 h/m
    assert_select "#history li", /Assigned to Marcus Reyes: site visit, Tue, Nov 24, 2026 · 2 pm/
    get admin_client_path(@maria)
    assert_match "Site visit booked for Tue, Nov 24, 2026 · 2 pm (request)", response.body, "named by its services (none here), not its R- reference"

    admin = member_with_role(:admin)
    assign(user_id: admin.id, kind: "call", scheduled_on: "2026-11-25", lock_version: follow_up.lock_version)
    get admin_service_request_path(@request_record)
    assert_select "#history li", /Handed from Marcus Reyes to Admin/
    assert_select "#history li", /Moved from Tue, Nov 24, 2026 · 2 pm to Wed, Nov 25, 2026 · 2 pm/
    assert_select "#history li", /Made it a call/

    delete admin_service_request_follow_up_path(@request_record)
    assert_nil follow_up
    follow_redirect!
    assert_select "#history li", /Taken off Admin/
    assert_select "#follow-up a", /Assign/

    assign(user_id: admin.id)
    as_business(@business) { BusinessUser.find_by(user: admin).deactivate! }
    get admin_service_request_path(@request_record)
    assert_select "#history li", /Taken off Admin: they left the team/
  end

  test "warnings come first, and Assign anyway goes ahead" do
    assign(start_time: "18:00")
    assert_response :unprocessable_content
    assert_select ".banner-warning li", "That's outside your hours (8 am–5 pm)."
    assert_select "input[type=submit][value='Assign anyway']"
    assert_nil follow_up

    digest = css_select("input[name=confirm]").first["value"]
    patch admin_service_request_follow_up_path(@request_record),
          params: { confirm: digest, request_follow_up: { user_id: @marcus.id, kind: "visit", scheduled_on: "2026-11-24", timing: "exact", start_time: "18:00" } }
    assert_redirected_to admin_service_request_path(@request_record)
    assert_equal "6 pm", follow_up.time_label

    patch admin_service_request_follow_up_path(@request_record), params: { request_follow_up: { user_id: @marcus.id, instructions: "Ring first",
                                                                                               lock_version: follow_up.lock_version } }
    assert_redirected_to admin_service_request_path(@request_record), "changing only the details doesn't warn again"
  end

  test "a stale form, and a request that's closed, are refused with a reason" do
    assign(fresh: "1")
    assign(fresh: "1", start_time: "09:00")
    assert_redirected_to edit_admin_service_request_follow_up_path(@request_record), "a form that showed nobody doesn't overwrite someone assigned since"
    assert_equal "2 pm", follow_up.time_label
    stale = follow_up.lock_version
    assign(start_time: "15:00", lock_version: stale)
    assign(start_time: "16:00", lock_version: stale)
    assert_redirected_to edit_admin_service_request_follow_up_path(@request_record)
    assert_equal "3 pm", follow_up.time_label

    patch status_admin_service_request_path(@request_record, status: "archived")
    assert_nil follow_up, "archiving ends the follow-up"
    get edit_admin_service_request_follow_up_path(@request_record)
    assert_redirected_to admin_service_request_path(@request_record)
    assert_match "archived", flash[:alert]
  end

  test "logging a request can assign it, with warnings first" do
    log = ->(**fields) do
      post admin_service_requests_path, params: { service_request: { client: @maria.uid, source: "phone", description: "Gutters" },
                                                  request_follow_up: { user_id: @marcus.id, kind: "call", scheduled_on: "2026-11-23", timing: "anytime" }.merge(fields) }
    end
    get new_admin_service_request_path
    assert_select "select[name='request_follow_up[user_id]'] option[value='']", "Not assigned"

    log.(scheduled_on: "2026-11-28")
    assert_response :unprocessable_content
    assert_select ".banner-warning li", "You're closed on Saturdays."
    assert_select "input[type=submit][value='Log request anyway']"
    assert_equal 1, as_business(@business) { ServiceRequest.count }

    log.()
    request = as_business(@business) { ServiceRequest.order(:id).last }
    assert_redirected_to admin_service_request_path(request)
    assert_equal "Request from Maria Lopez logged and given to Marcus Reyes.", flash[:notice]
    assert_equal [ "in_progress", "call", @marcus ], as_business(@business) { [ request.status, request.follow_up.kind, request.follow_up.user ] }

    log.(user_id: "")
    assert_equal [ "new", nil ], as_business(@business) { ServiceRequest.order(:id).last.then { [ _1.status, _1.follow_up ] } }, "nobody picked, nobody assigned"
  end

  test "a custom role with office access can be assigned; once it can't see requests, the form won't keep them by accident" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    role = as_business(@business) { Role.create!(name: "Coordinator", permissions: %w[office]) }
    cora = User.create!(email: "cora@example.com", password: "password123", first_name: "Cora", last_name: "Park", confirmed_at: Time.current)
    BusinessUser.create!(user: cora, business: @business, role: "custom", role_id: role.id)
    assign(user_id: cora.id)
    assert_equal cora, follow_up.user

    as_business(@business) { role.update!(permissions: %w[schedule]) } # the role itself changes: nobody is told
    get edit_admin_service_request_follow_up_path(@request_record)
    assert_select "select[name='request_follow_up[user_id]'] option[disabled][value=?]", cora.id.to_s, /Cora Park \(can't keep it/
    assert_select "select[name='request_follow_up[user_id]'] option[selected][value='']", "Choose someone"
    assign(user_id: "", lock_version: follow_up.lock_version)
    assert_response :unprocessable_content
    assert_equal cora, follow_up.user, "not handed to anyone silently"
  end

  test "a blank duration stays blank after a warning, a bad field set is refused, and the Overdue badge shows" do
    assign(start_time: "18:00", duration_hours: "")
    assert_select "input[name='request_follow_up[duration_hours]'][value='']"
    assign(start_time: "18:00", duration_hours: "0")
    assert_select "#request_follow_up_duration_hours[aria-invalid=true]"
    assert_select ".error-text", "Give a duration between 5 minutes and 24 hours."

    patch admin_service_request_follow_up_path(@request_record), params: { request_follow_up: "nonsense" }
    assert_response :bad_request

    patch admin_service_request_follow_up_path(@request_record), params: { request_follow_up: { user_id: @marcus.id, scheduled_on: "" } }
    assert_select ".error-text", "Choose a day."

    assign(scheduled_on: "2026-11-20")
    get admin_service_request_path(@request_record)
    assert_select "#follow-up .badge", "Overdue"
  end

  test "unassigning from a stale page is refused; with nobody on it, it says so" do
    assign
    stale = follow_up.lock_version
    assign(start_time: "15:00", lock_version: stale)
    delete admin_service_request_follow_up_path(@request_record), params: { lock_version: stale }
    assert_equal "Someone else changed this follow-up meanwhile. Here's the latest.", flash[:alert]
    assert follow_up
    delete admin_service_request_follow_up_path(@request_record), params: { lock_version: follow_up.lock_version }
    assert_nil follow_up
    delete admin_service_request_follow_up_path(@request_record)
    assert_equal "Nobody had it.", flash[:notice]
  end

  test "logging a request with a follow-up that doesn't add up shows the form again, with nothing saved" do
    get new_admin_service_request_path
    assert_select "div.group\\/assignee"
    assert_select "input[name='request_follow_up[scheduled_on]'][required]", 0, "a hidden day can't block logging with nobody picked"
    post admin_service_requests_path, params: { service_request: { client: @maria.uid, source: "phone", description: "Gutters" },
                                                request_follow_up: { user_id: @marcus.id, kind: "visit", scheduled_on: "2026-11-24", timing: "exact", start_time: "" } }
    assert_response :unprocessable_content
    assert_select "textarea[name='service_request[description]']", "Gutters"
    assert_select ".error-text", /needs a time/
    assert_equal 1, as_business(@business) { ServiceRequest.count }
  end
end
