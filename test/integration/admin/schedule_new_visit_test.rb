require "test_helper"

# QA #274 (WCAG 2.1.1): every pointer action on the calendar has a keyboard way. Each empty hour
# is a named link to a new visit there; it asks which job, then opens the job's visit form with
# the day, time and person filled in, and comes back to the calendar with focus on the visit.
# Also the heading's year and time zone, and the "Nobody yet" count's unit.
class Admin::ScheduleNewVisitTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @tech = member_with_role(:technician)
    @monday = Date.new(2026, 11, 23)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @booked = Job.create!(client: @maria, title: "Spring cleanup")
      @booked.visits.new(scheduled_on: @monday, timing: "exact", start_time: "09:00", duration_minutes: 60).schedule!(by: @owner)
      @waiting = Job.create!(client: @maria, title: "Gutter cleaning")
      Job.create!(client: @maria, title: "Old fence").tap { _1.update_columns(status: "completed") }
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def on_monday(&) = travel_to(@business.local_time(@monday, "07:00"), &)

  test "each empty hour from today on is a named link to a new visit there; the heading has the year and the clock" do
    on_monday do
      get admin_schedule_path(date: @monday.iso8601)
      assert_select "h1", "Schedule: November 23 – 29, 2026"
      assert_select ".page-lede", "Week view · Times in Eastern Time (US & Canada)"
      assert_select "nav[aria-label=View] a[aria-current=page]", "Week"
      slots = css_select("#schedule-grid a.cal-slot")
      assert_equal 7 * 9, slots.size, "8 am to 5 pm, every day of the week"
      slot = css_select("#schedule-grid a.cal-slot").find { _1.text.include?("Tuesday, November 24, 9:00 AM") }
      assert_equal "New visit, Tuesday, November 24, 9:00 AM", slot.at_css(".sr-only").text
      assert_equal "schedule-slots-help", slot["aria-describedby"]
      assert_equal admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", view: "week"), slot["href"]
      assert_select "#schedule-grid a.cal-slot[data-start=true]", 1
      assert_select "#schedule-grid a.cal-slot[data-start=true] .sr-only", "New visit, Monday, November 23, 9:00 AM"
      assert_select "#schedule-members li", text: /Nobody yet\s*1 visit/
      assert_select "a[href=?]", admin_schedule_new_visit_path(on: @monday.iso8601, view: "week"), text: /New visit/

      get admin_schedule_path(date: (@monday + 7).iso8601)
      assert_select "#schedule-grid a.cal-slot", 7 * 9
      travel 3.days
      get admin_schedule_path(date: @monday.iso8601)
      assert_select "#schedule-grid a.cal-slot", 4 * 9, "past days aren't bookable"

      get admin_schedule_path(view: "day", date: (@monday + 4).iso8601)
      assert_select "h1", "Schedule: Friday, November 27, 2026"
      assert_select "#schedule-grid a.cal-slot .sr-only", text: "New visit, Friday, November 27, 10:00 AM, with #{@tech.full_name}"
      assert_select "#schedule-grid a.cal-slot[href=?]", admin_schedule_new_visit_path(on: "2026-11-27", at: "10:00", member: @tech.id, view: "day")
    end
  end

  test "a slot asks which job, then opens its visit form with the day, time and person; booking it comes back to the calendar" do
    on_monday do
      get admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", member: @tech.id, view: "day"), headers: { "Turbo-Frame" => "schedule_visit" }
      assert_select "turbo-frame#schedule_visit h2", "New visit"
      assert_select "turbo-frame#schedule_visit", text: /Tuesday, November 24, 2026 · 9:00 AM · with #{@tech.full_name}/
      assert_select "label[for=new-visit-job]", "Job"
      assert_select "select#new-visit-job[required]" do
        assert_select "optgroup[label='Needs scheduling'] option[value=?]", @waiting.uid
        assert_select "optgroup[label='Other open jobs'] option[value=?]", @booked.uid
        assert_select "option", text: /Old fence/, count: 0
      end
      assert_select "a[href=?]", admin_clients_path, 0, "no layout inside the frame"

      get admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", member: @tech.id, view: "day", job: @waiting.uid)
      assert_redirected_to new_admin_job_visit_path(@waiting, on: "2026-11-24", at: "09:00", member: @tech.id, from: "schedule", view: "day")
      follow_redirect!
      assert_select "input[name='visit[scheduled_on]'][value='2026-11-24']"
      assert_select "input#timing-exact[checked]"
      assert_select "input[name='visit[start_time]'][value='09:00']"
      assert_select "input[name='visit[assignee_ids][]'][value=?][checked]", @tech.id.to_s
      assert_select "input[type=hidden][name=from][value=schedule]"
      assert_select "a[href=?]", admin_schedule_path(date: "2026-11-24", view: "day"), text: "Cancel"

      post admin_job_visits_path(@waiting), params: { from: "schedule", view: "day", visit: { scheduled_on: "2026-11-24", timing: "exact", start_time: "09:00", duration_hours: "1", assignee_ids: [ "", @tech.id.to_s ] } }
      visit = as_business(@business) { @waiting.visits.sole }
      assert_redirected_to admin_schedule_path(date: "2026-11-24", view: "day", focus: visit.uid)
      follow_redirect!
      assert_select "[data-schedule-focus=?]", visit.uid, minimum: 1
    end
  end

  test "a past day starts today, a bad time or someone off the team is left out, and the full page works without the panel" do
    on_monday do
      get admin_schedule_new_visit_path(on: "2026-11-01", at: "25:00", member: users(:two).id)
      assert_response :success
      assert_select "h2", "New visit"
      assert_select "p.card-subtitle", "Monday, November 23, 2026"
      assert_select "a[href=?]", admin_schedule_path(date: @monday.iso8601), text: /Schedule/
      get admin_schedule_new_visit_path(on: "2026-11-24", at: "25:00", member: users(:two).id, job: @waiting.uid)
      assert_redirected_to new_admin_job_visit_path(@waiting, on: "2026-11-24", from: "schedule")
    end
  end

  test "only people who schedule get it, and another business's jobs aren't offered or found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_schedule_new_visit_path }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      Job.create!(client: Client.create!(display_name: "Their client", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ]), title: "Theirs")
    end
    get admin_schedule_new_visit_path
    assert_select "option", text: /Theirs/, count: 0
    assert_not_found_across_businesses { get admin_schedule_new_visit_path(job: theirs.uid) }
  end
end
