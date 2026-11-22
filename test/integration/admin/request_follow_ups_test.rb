require "test_helper"

# CLI-07: assigning requests from the request page and when logging one; moving, handing on and
# unassigning; warnings; who may do it.
class Admin::RequestFollowUpsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @tech = member_with_role(:technician)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @request_record = ServiceRequest.create!(client: @maria, source: "phone", description: "Fence repair")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def assign(**fields)
    patch admin_service_request_follow_up_path(@request_record),
          params: { request_follow_up: { user_id: @tech.id, kind: "visit", scheduled_on: "2026-11-24", timing: "exact", start_time: "14:00", window_end_time: "",
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
    assert_select ".error-text", /Choose who follows it up/
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
    assert_select "select[name='request_follow_up[user_id]'] option", /Technician \(Technician\)/

    assign
    assert_redirected_to admin_service_request_path(@request_record)
    assert_equal "Technician has it: site visit, Tue, Nov 24 · 2 pm.", flash[:notice]
    assert_equal [ @tech, "2 pm", 60, "Check the back gate" ], [ follow_up.user, follow_up.time_label, follow_up.duration_minutes, follow_up.instructions ]
    assert_equal "in_progress", as_business(@business) { @request_record.reload.status }
    follow_redirect!
    assert_select "#follow-up", /Technician.*Site visit, Tue, Nov 24 · 2 pm.*About 1 h/m
    assert_select "#history li", /Assigned to Technician: site visit, Tue, Nov 24, 2026 · 2 pm/

    admin = member_with_role(:admin)
    assign(user_id: admin.id, kind: "call", scheduled_on: "2026-11-25", lock_version: follow_up.lock_version)
    get admin_service_request_path(@request_record)
    assert_select "#history li", /Handed from Technician to Admin/
    assert_select "#history li", /Moved from Tue, Nov 24, 2026 · 2 pm to Wed, Nov 25, 2026 · 2 pm/
    assert_select "#history li", /Made it a call/

    delete admin_service_request_follow_up_path(@request_record)
    assert_nil follow_up
    follow_redirect!
    assert_select "#history li", /Taken off Admin/
    assert_select "#follow-up a", /Assign/
  end

  test "warnings come first, and Assign anyway goes ahead" do
    assign(start_time: "18:00")
    assert_response :unprocessable_content
    assert_select ".banner-warning li", "That's outside your hours (8 am–5 pm)."
    assert_select "input[type=submit][value='Assign anyway']"
    assert_nil follow_up

    digest = css_select("input[name=confirm]").first["value"]
    patch admin_service_request_follow_up_path(@request_record),
          params: { confirm: digest, request_follow_up: { user_id: @tech.id, kind: "visit", scheduled_on: "2026-11-24", timing: "exact", start_time: "18:00" } }
    assert_redirected_to admin_service_request_path(@request_record)
    assert_equal "6 pm", follow_up.time_label

    patch admin_service_request_follow_up_path(@request_record), params: { request_follow_up: { user_id: @tech.id, kind: "call", instructions: "Ring first",
                                                                                               lock_version: follow_up.lock_version } }
    assert_redirected_to admin_service_request_path(@request_record), "changing only the details doesn't warn again"
  end

  test "a stale form, and a request that's closed, are refused with a reason" do
    assign
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
                                                  request_follow_up: { user_id: @tech.id, kind: "call", scheduled_on: "2026-11-23", timing: "anytime" }.merge(fields) }
    end
    get new_admin_service_request_path
    assert_select "select[name='request_follow_up[user_id]'] option[value='']", "Nobody yet"

    log.(scheduled_on: "2026-11-28")
    assert_response :unprocessable_content
    assert_select ".banner-warning li", "You're closed on Saturdays."
    assert_select "input[type=submit][value='Log request anyway']"
    assert_equal 1, as_business(@business) { ServiceRequest.count }

    log.()
    request = as_business(@business) { ServiceRequest.order(:id).last }
    assert_redirected_to admin_service_request_path(request)
    assert_equal "Request from Maria Lopez logged and given to Technician.", flash[:notice]
    assert_equal [ "in_progress", "call", @tech ], as_business(@business) { [ request.status, request.follow_up.kind, request.follow_up.user ] }

    log.(user_id: "")
    assert_equal [ "new", nil ], as_business(@business) { ServiceRequest.order(:id).last.then { [ _1.status, _1.follow_up ] } }, "nobody picked, nobody assigned"
  end
end
