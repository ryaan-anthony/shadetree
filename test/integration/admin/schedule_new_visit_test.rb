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
      assert_nil slot["aria-describedby"], "the arrow-key help is attached by the script that makes the keys work"
      assert_select "#schedule-slots-help", text: /Home and End.*Enter or Space/
      assert_equal "slot-2026-11-24-09-all", slot["data-schedule-focus"]
      assert_equal admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", view: "week", slot: "slot-2026-11-24-09-all"), slot["href"]
      assert_select "#schedule-grid a.cal-slot[data-start=true]", 1
      assert_select "#schedule-grid a.cal-slot[data-start=true] .sr-only", "New visit, Monday, November 23, 9:00 AM"
      assert_select "#schedule-members li", text: /Nobody yet\s*1 visit/
      assert_select "a[href=?]", admin_schedule_new_visit_path(on: @monday.iso8601, view: "week"), text: /New visit/
      assert_select ".cal-grid div", text: "Anytime", count: 1 do |label|
        assert_includes label.first["class"], "text-muted", "4.58:1 on the anytime row (QA #274)"
      end

      get admin_schedule_path(date: @monday.iso8601, member: @tech.id)
      assert_select "#schedule-grid a.cal-slot[href=?]", admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", crew: @tech.id, view: "week", member: @tech.id, slot: "slot-2026-11-24-09-all"),
                    1, "filtered to one person: the slot books them, and the filter is kept"

      get admin_schedule_path(date: (@monday + 7).iso8601)
      assert_select "#schedule-grid a.cal-slot", 7 * 9
      travel 3.days
      get admin_schedule_path(date: @monday.iso8601)
      assert_select "#schedule-grid a.cal-slot", 4 * 9, "past days aren't bookable"

      get admin_schedule_path(view: "day", date: (@monday + 4).iso8601)
      assert_select "h1", "Schedule: Friday, November 27, 2026"
      assert_select "#schedule-grid a.cal-slot .sr-only", text: "New visit, Friday, November 27, 10:00 AM, with #{@tech.full_name}"
      assert_select "#schedule-grid a.cal-slot[href=?]", admin_schedule_new_visit_path(on: "2026-11-27", at: "10:00", crew: @tech.id, view: "day", slot: "slot-2026-11-27-10-#{@tech.id}")
    end
  end

  test "a slot asks which job, then opens its visit form with the day, time and person; booking it comes back to the calendar" do
    on_monday do
      slot = "slot-2026-11-24-09-#{@tech.id}"
      calendar = { view: "day", member: @tech.id.to_s, slot: }
      get admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", crew: @tech.id, **calendar), headers: { "Turbo-Frame" => "schedule_visit" }
      assert_select "turbo-frame#schedule_visit h2", "New visit"
      assert_select "turbo-frame#schedule_visit", text: /Tuesday, November 24, 2026 · 9:00 AM · with #{@tech.full_name}/
      assert_select "label[for=new-visit-job]", "Job"
      assert_select "select#new-visit-job[required]" do
        assert_select "optgroup[label='Needs scheduling'] option[value=?]", @waiting.uid
        assert_select "optgroup[label='Other open jobs'] option[value=?]", @booked.uid
        assert_select "option", text: /Old fence/, count: 0
      end
      assert_select "a[href=?]", admin_clients_path, 0, "no layout inside the frame"
      assert_select "input[type=hidden][name=crew][value=?]", @tech.id.to_s
      assert_select "input[type=hidden][name=slot][value=?]", slot
      assert_select "input[type=hidden][name=member][value=?]", @tech.id.to_s
      assert_not response.headers["Set-Cookie"].to_s.include?("_session"), "the frame load leaves the session alone (an Undo's flash survives it)"

      get admin_schedule_new_visit_path(on: "2026-11-24", at: "09:00", crew: @tech.id, job: @waiting.uid, **calendar)
      assert_redirected_to new_admin_job_visit_path(@waiting, on: "2026-11-24", at: "09:00", crew: @tech.id, from: "schedule", **calendar)
      follow_redirect!
      assert_select "input[name='visit[scheduled_on]'][value='2026-11-24']"
      assert_select "input#timing-exact[checked]"
      assert_select "input[name='visit[start_time]'][value='09:00']"
      assert_select "input[name='visit[assignee_ids][]'][value=?][checked]", @tech.id.to_s
      assert_select "input[type=hidden][name=from][value=schedule]"
      assert_select "input[type=hidden][name=slot][value=?]", slot
      assert_select "a[href=?]", admin_schedule_path(date: "2026-11-24", view: "day", member: @tech.id, focus: slot), text: "Cancel"

      post admin_job_visits_path(@waiting), params: { from: "schedule", **calendar, visit: { scheduled_on: "2026-11-24", timing: "exact", start_time: "09:00", duration_hours: "1", assignee_ids: [ "", @tech.id.to_s ] } }
      visit = as_business(@business) { @waiting.visits.sole }
      assert_redirected_to admin_schedule_path(date: "2026-11-24", view: "day", member: @tech.id, focus: "#{visit.uid},#{slot}"), "the new visit, else the slot"
      follow_redirect!
      assert_select "[data-schedule-focus=?]", visit.uid, minimum: 1
      assert_select "[data-schedule-focus=?]", "slot-2026-11-24-10-all", 1, "slots carry their focus key (one column: filtered to a person)"

      get new_admin_job_visit_path(@waiting, from: "schedule", slot: "../evil", member: "x", view: "month")
      assert_select "input[type=hidden][name=slot]", 0, "what comes back is checked"
      assert_select "a[href=?]", admin_schedule_path(date: @monday.iso8601), text: "Cancel"
    end
  end

  test "a past day starts today, a bad time or someone off the team or not doing field work is left out, and the full page has its own heading" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    office = User.create!(email: "office-#{SecureRandom.hex(4)}@example.com", password: "password123", first_name: "Olive", confirmed_at: Time.current)
    as_business(@business) { BusinessUser.create!(user: office, business: @business, role: "custom", role_id: Role.create!(name: "Office", permissions: %w[office schedule]).id) }
    on_monday do
      get admin_schedule_new_visit_path(on: "2026-11-01", at: "25:00", crew: users(:two).id, view: "day", slot: "slot-2026-11-23-09-all")
      assert_response :success
      assert_select "h1", "New visit"
      assert_select ".page-lede", "Monday, November 23, 2026"
      assert_select "h2", { text: "New visit", count: 0 }, "one heading on its own page"
      assert_select "a[href=?]", admin_schedule_path(date: @monday.iso8601, view: "day", focus: "slot-2026-11-23-09-all"), text: /Schedule/
      get admin_schedule_new_visit_path(on: "2026-11-24", at: "25:00", crew: users(:two).id, job: @waiting.uid)
      assert_redirected_to new_admin_job_visit_path(@waiting, on: "2026-11-24", from: "schedule")
      get admin_schedule_new_visit_path(on: "2026-11-24", crew: office.id)
      assert_select ".page-lede", "Tuesday, November 24, 2026", "someone who doesn't do field work isn't put on it"
      get admin_schedule_new_visit_path(on: "2026-11-24", crew: office.id, job: @waiting.uid)
      assert_redirected_to new_admin_job_visit_path(@waiting, on: "2026-11-24", from: "schedule")
    end
  end

  test "a long list of open jobs says it's cut off and where to find the rest" do
    as_business(@business) do
      now = Time.current
      rows = (Admin::ScheduleController::NEW_VISIT_JOBS + 1).times.map do |n|
        { business_id: @business.id, uid: SecureRandom.alphanumeric(12), number: "J-9#{format("%03d", n)}", client_id: @maria.id, title: "Bulk #{n}", status: "unscheduled",
          currency: "USD", location_id: @waiting.location_id, created_at: now, updated_at: now }
      end
      Job.insert_all!(rows)
    end
    get admin_schedule_new_visit_path
    assert_select "#new-visit-job option[value]:not([value=''])", Admin::ScheduleController::NEW_VISIT_JOBS
    assert_select "#new-visit-job-help", text: /Only the first 200 open jobs are listed.*find it in Jobs and choose Schedule visit/m
    assert_select "#new-visit-job-help a[href=?]", admin_jobs_path(filter: "open")
  end

  test "the day starts no earlier than today on the job's own clock" do
    as_business(@business) do
      @business.update!(plan_overrides: { "features" => { "locations" => true } })
      @far = Location.create!(name: "Honolulu yard", timezone: "Pacific/Honolulu")
      @waiting.update!(location: @far)
    end
    # 2 am Tuesday in New York is still Monday in Honolulu.
    travel_to @business.local_time(@monday + 1, "02:00") do
      get new_admin_job_visit_path(@waiting, on: @monday.iso8601)
      assert_equal @monday.iso8601, css_select("input[name='visit[scheduled_on]']").sole["value"], "Monday is still today in Honolulu"
      get new_admin_job_visit_path(@booked, on: @monday.iso8601)
      assert_equal (@monday + 1).iso8601, css_select("input[name='visit[scheduled_on]']").sole["value"], "a job in New York starts on Tuesday"
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
