require "test_helper"

# JOB-03: moving visits on the calendar: dragged (JSON) or from the quick-edit sheet (a form),
# with JOB-02's warnings, a toast with Undo, and the usual permissions and tenancy.
class Admin::ScheduleMovesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @tech = member_with_role(:technician)
    @other = member_with_role(:technician)
    @monday = Date.new(2026, 11, 23)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: maria, title: "Spring cleanup")
      @visit = book(@monday, timing: "window", start_time: "09:00", window_end_time: "11:00", duration_minutes: 60, assignee_ids: [ @tech.id ])
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def book(on, **fields) = @job.visits.new(scheduled_on: on, **fields).tap { _1.schedule!(by: @owner) }

  def drag(visit = @visit, **params)
    patch admin_schedule_move_path(visit), params: { lock_version: visit.reload.lock_version, **params }, as: :json
  end

  def fresh = as_business(@business) { @visit.reload.tap { _1.assignments.load } }

  test "dragged to another day and time: a window keeps its length; the toast offers Undo, which puts it back" do
    drag(on: (@monday + 2).iso8601, at: "13:30", view: "week")
    assert_response :ok
    assert_equal [ @monday + 2, "13:30", "15:30", [ @tech.id ] ], fresh.then { [ _1.scheduled_on, _1.start_time, _1.window_end_time, _1.assignee_ids ] }
    assert_equal "rescheduled", as_business(@business) { @visit.events.last.kind }

    get admin_schedule_path(date: @monday.iso8601)
    assert_select "#flash", text: /Moved: Maria Lopez, Wed, Nov 25 · Arrive 1:30–3:30 pm/
    undo = css_select("#flash form").sole
    assert_equal admin_schedule_move_path(@visit), undo["action"]
    fields = undo.css("input[type=hidden]").to_h { [ _1["name"], _1["value"] ] }
    assert_equal [ @monday.iso8601, "09:00", @tech.id.to_s, "1", "week" ], fields.values_at("on", "at", "crew[]", "undo", "view")

    patch undo["action"], params: fields
    assert_redirected_to admin_schedule_path(view: "week", date: @monday.iso8601)
    assert_equal [ @monday, "09:00", "11:00" ], fresh.then { [ _1.scheduled_on, _1.start_time, _1.window_end_time ] }
    follow_redirect!
    assert_select "#flash", text: /Put back: Maria Lopez, Mon, Nov 23/
    assert_select "#flash form", 0, "no undo of an undo"
  end

  test "dragged from one person to another, or to nobody; someone else on the visit stays" do
    as_business(@business) { @visit.reschedule!({ assignee_ids: [ @tech.id, @owner.id ] }, by: @owner) }
    drag(on: @monday.iso8601, at: "09:00", from: @tech.id, to: @other.id)
    assert_equal [ @owner.id, @other.id ].sort, fresh.assignee_ids.sort
    drag(on: @monday.iso8601, at: "09:00", from: @other.id, to: "none")
    assert_equal [ @owner.id ], fresh.assignee_ids
    assert_match "· John", flash[:notice]

    drag(on: @monday.iso8601, from: @owner.id, to: users(:two).id)
    assert_response :unprocessable_content
    assert_equal "That person isn't on your team.", response.parsed_body["error"]
  end

  test "the same warnings as the visit form; sent again with their digest, it moves" do
    drag(on: (@monday + 6).iso8601, at: "09:00")
    assert_response :unprocessable_content
    assert_equal [ "You're closed on Sundays." ], response.parsed_body["warnings"]
    assert_equal @monday, fresh.scheduled_on

    drag(on: (@monday + 6).iso8601, at: "09:00", confirm: "something else")
    assert_response :unprocessable_content
    drag(on: (@monday + 6).iso8601, at: "09:00", confirm: response.parsed_body["confirm"])
    assert_response :ok
    assert_equal @monday + 6, fresh.scheduled_on
  end

  test "refused: someone else changed it, a finished visit, a bad time, a window past midnight" do
    stale = fresh.lock_version
    as_business(@business) { @visit.reschedule!({ duration_minutes: 90 }, by: @owner) }
    patch admin_schedule_move_path(@visit), params: { on: @monday.iso8601, lock_version: stale }, as: :json
    assert_response :conflict
    assert_equal @monday, fresh.scheduled_on

    drag(on: @monday.iso8601, at: "9am")
    assert_equal "Choose a time like 09:30.", response.parsed_body["error"]
    drag(on: @monday.iso8601, at: "23:00")
    assert_equal "That window would run past midnight.", response.parsed_body["error"]
    drag(on: "next week")
    assert_equal "Choose a day.", response.parsed_body["error"]

    as_business(@business) { @visit.complete!(by: @owner) }
    drag(on: (@monday + 1).iso8601)
    assert_response :unprocessable_content
    assert_equal @monday, fresh.scheduled_on
  end

  test "the quick-edit sheet: warnings come back in it with what was asked; Move anyway moves it" do
    get admin_schedule_visit_path(@visit)
    assert_select "dialog#move-#{@visit.uid}.modal-sheet form[action=?]", admin_schedule_move_path(@visit)
    assert_select "dialog#move-#{@visit.uid} input[name='crew[]'][value=?][checked]", @tech.id.to_s

    form = { on: (@monday + 5).iso8601, at: "10:00", crew: [ "", @other.id ], lock_version: fresh.lock_version }
    patch admin_schedule_move_path(@visit), params: form
    assert_response :unprocessable_content
    assert_select "[data-controller=modal][data-modal-open-value=true] .banner-warning", text: /You're closed on Saturdays/
    assert_select "input[name=on][value=?]", (@monday + 5).iso8601
    assert_select "input[name='crew[]'][value=?][checked]", @other.id.to_s
    assert_select "input[name='crew[]'][value=?]:not([checked])", @tech.id.to_s
    assert_select "header", text: /Mon, Nov 23/, minimum: 0
    assert_select "dd", text: /Technician/, minimum: 1 # the details show it as it is
    assert_select "input[type=submit][value='Move anyway']"

    patch admin_schedule_move_path(@visit), params: form.merge(confirm: css_select("input[name=confirm]").sole["value"])
    assert_redirected_to admin_schedule_path(date: (@monday + 5).iso8601)
    assert_equal [ @monday + 5, "10:00", [ @other.id ] ], fresh.then { [ _1.scheduled_on, _1.start_time, _1.assignee_ids ] }

    patch admin_schedule_move_path(@visit), params: { on: (@monday + 1).iso8601, at: "10:00", crew: [ "" ], lock_version: fresh.lock_version }
    assert_empty fresh.assignee_ids, "unticking everyone leaves nobody on it"
  end

  test "only Owners and Admins move visits, and another business's visits aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { drag(on: @monday.iso8601) }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs").visits.new(scheduled_on: @monday, timing: "anytime").tap { _1.schedule!(by: nil) }
    end
    assert_not_found_across_businesses { patch admin_schedule_move_path(theirs), params: { on: @monday.iso8601 }, as: :json }
  end
end
