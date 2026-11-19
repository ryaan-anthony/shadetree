require "test_helper"

# JOB-03: the team calendar. Week and day views on a time grid, the agenda on phones, filters,
# shading for closed time, the jobs needing a visit, and a visit's details.
class Admin::ScheduleTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @tech = member_with_role(:technician)
    @monday = Date.new(2026, 11, 23)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", city: "Asheville", region: "NC", postal_code: "28801" } ])
      @job = Job.create!(client: @maria, property: @maria.properties.first, title: "Spring cleanup")
      @timed = book(@monday, timing: "exact", start_time: "09:00", duration_minutes: 90, assignee_ids: [ @tech.id ])
      @anytime = book(@monday + 2, timing: "anytime", duration_minutes: 60, assignee_ids: [ @owner.id ])
      @nobody = book(@monday + 3, timing: "window", start_time: "13:00", window_end_time: "15:00", duration_minutes: 60)
      @cancelled = book(@monday + 1, timing: "exact", start_time: "10:00", duration_minutes: 60).tap { _1.cancel!(by: @owner) }
      @waiting = Job.create!(client: @maria, property: @maria.properties.first, title: "Gutter cleaning")
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def book(on, **fields) = @job.visits.new(scheduled_on: on, **fields).tap { _1.schedule!(by: @owner) }

  def week(**params) = get(admin_schedule_path(date: @monday.iso8601, **params))

  test "Owners and Admins see the calendar; technicians use My day and don't get the link" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_schedule_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_schedule_visit_path(@timed) }
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_redirected_to admin_my_day_path
    follow_redirect!
    assert_response :success
    assert_select "a[href=?]", admin_schedule_path, 0
  end

  test "another business's visits aren't shown or found" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Their client", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs").visits.new(scheduled_on: @monday, timing: "anytime").tap { _1.schedule!(by: nil) }
    end
    week
    assert_select "#schedule-grid", text: /Their client/, count: 0
    assert_not_found_across_businesses { get admin_schedule_visit_path(theirs) }
  end

  test "the week shows visits by time with who, where and what; anytime ones in their own row; cancelled ones aren't shown" do
    week
    assert_select "h1", "November 23 – 29"
    assert_select "#schedule-grid .cal-day", 7
    assert_select "#cal-visit-#{@timed.uid}.cal-visit", text: /9 am Maria Lopez, Monday, November 23.*Spring cleanup, Asheville.*Technician/m
    assert_select "#schedule-grid [role=group][aria-label='Monday, November 23']"
    assert_select "#cal-visit-#{@anytime.uid}.cal-chip", text: /Maria Lopez.*anytime Wednesday, November 25.*Spring cleanup, Asheville · John/m
    assert_select "#cal-visit-#{@nobody.uid}", text: /1–3 pm.*Nobody yet/m
    assert_select "#cal-visit-#{@cancelled.uid}", 0
    assert_select "#schedule-agenda", text: /Monday, Nov 23.*9 am.*Maria Lopez/m
    assert_select "a[aria-label='Previous week'][href=?]", admin_schedule_path(view: "week", date: (@monday - 7).iso8601)
    assert_select "a[aria-label='Next week'][href=?]", admin_schedule_path(view: "week", date: (@monday + 7).iso8601)

    get admin_schedule_path(view: "day", date: @monday.iso8601)
    assert_select "h1", "Monday, November 23"
    assert_select "#schedule-grid .cal-day", 3, "a day for everyone has a column per person, and one for nobody yet"
    assert_select "#schedule-grid .cal-day[aria-label='Monday, November 23, Technician'] #cal-visit-#{@timed.uid}-#{@tech.id}"
    assert_select "#schedule-grid [id^=cal-visit-#{@anytime.uid}]", 0
    get admin_schedule_path(view: "day", date: @monday.iso8601, member: @tech.id)
    assert_select "#schedule-grid .cal-day", 1
    assert_select "#cal-visit-#{@timed.uid}"

    get admin_schedule_path(date: "2026-W48-1")
    assert_response :success, "a date that isn't YYYY-MM-DD falls back to today"
    assert_select "h1", /#{@business.today.strftime("%B")}/

    get admin_schedule_path(date: "2027-12-29")
    assert_select "h1", "Dec 27, 2027 – Jan 2, 2028", "a week across the year says which"
    assert_select "#schedule-agenda", text: /Nothing booked this week/
  end

  test "filter by member, or the visits nobody's on yet; colors by person or status" do
    week(member: @tech.id)
    assert_select "#schedule-grid [id^=cal-visit-]", 1
    assert_select "#cal-visit-#{@timed.uid}"
    week(member: "unassigned")
    assert_select "#schedule-grid [id^=cal-visit-]", 1
    assert_select "#cal-visit-#{@nobody.uid}.cal-none"
    week(member: users(:two).id) # not in this business: ignored, everyone shown
    assert_select "#schedule-grid [id^=cal-visit-]", 3
    assert_select "#schedule-members li", text: /Technician\s*1.5 h/
    as_business(@business) { BusinessUser.find_by!(user: @tech).update!(active: false) }
    week(member: @tech.id)
    assert_select "#schedule-grid [id^=cal-visit-]", 3, "someone no longer on the team isn't a filter"
    assert_select "#cal-visit-#{@timed.uid}.cal-none", 1, "their visits aren't shown in someone else's color"
    as_business(@business) { BusinessUser.find_by!(user: @tech).update!(active: true) }

    week(color: "status")
    assert_select "#cal-visit-#{@timed.uid}.cal-status-scheduled"
    assert_select "a", text: "status", count: 0
    assert_select "a[href=?]", admin_schedule_path(view: "week", date: @monday.iso8601), text: "person"
  end

  test "off-hours and closures are shaded" do
    as_business(@business) { Closure.create!(reason: "Thanksgiving", starts_on: @monday + 3) }
    week
    days = css_select("#schedule-grid .cal-day")
    assert_equal 0, days[0].css(".cal-shade").size, "Monday 8–5: the grid is the open hours, nothing to shade"
    assert_equal 1, days[3].css(".cal-shade").size, "Thursday is closed all day"
    assert_equal 1, days[5].css(".cal-shade").size, "Saturday too"
    assert_select "#schedule-grid", text: /Closed: Thanksgiving/
  end

  test "jobs needing a visit are listed, and scheduling one starts on the day being viewed" do
    week
    assert_select "#needs-scheduling", text: /Gutter cleaning/
    assert_select "#needs-scheduling", text: /Spring cleanup/, count: 0
    link = css_select("#needs-scheduling a[aria-label='Schedule #{@waiting.number}']").sole["href"]
    travel_to @business.local_time(@monday - 1, "12:00") do
      get link
      assert_select "input[name='visit[scheduled_on]'][value=?]", @monday.iso8601
      get new_admin_job_visit_path(@waiting, on: (@monday - 14).iso8601)
      assert_equal (@monday - 1).iso8601, css_select("input[name='visit[scheduled_on]']").sole["value"], "a past week's Schedule starts today"
    end
  end

  test "opening a visit shows its details beside the calendar, or on its own page on a phone" do
    get admin_schedule_visit_path(@timed), headers: { "Turbo-Frame" => "schedule_visit" }
    assert_select "turbo-frame#schedule_visit", text: /Maria Lopez.*#{@job.number} Spring cleanup.*12 Elm St.*Technician/m
    assert_select "a[href=?]", admin_job_path(@job, anchor: "visit-#{@timed.uid}")
    assert_select "a[href=?]", edit_admin_job_visit_path(@job, @timed)
    assert_select "a[href=?]", admin_clients_path, 0, "no layout inside the frame"
    assert_not response.headers["Set-Cookie"].to_s.include?("_session"), "the panel's frame load leaves the session alone (an Undo's flash survives it)"

    get admin_schedule_visit_path(@timed)
    assert_select "a[href=?]", admin_schedule_path(date: @monday.iso8601), text: /Schedule/
    assert response.headers["Set-Cookie"].to_s.include?("_session"), "the full page (phones) writes the session as usual"
  end

  test "hovering the calendar doesn't prefetch visits (a late prefetch would wipe an Undo's flash)" do
    get admin_schedule_path(date: @monday.iso8601)
    assert_select "#schedule-grid[data-turbo-prefetch=false]"
  end

  test "a week of 200 visits for 10 people loads in a fixed number of queries" do
    as_business(@business) do
      crew = 9.times.map { member_with_role(:technician) } + [ @tech ]
      rows = 200.times.map do |n|
        { job_id: @job.id, business_id: @business.id, scheduled_on: @monday + (n % 7), timing: "exact", starts_at: @business.local_time(@monday + (n % 7), format("%02d:00", 7 + (n % 10))),
          duration_minutes: 60, status: "scheduled", uid: SecureRandom.alphanumeric(12), created_at: Time.current, updated_at: Time.current }
      end
      ids = Visit.insert_all!(rows, returning: :id).map { _1["id"] }
      VisitAssignment.insert_all!(ids.each_with_index.map { |id, n| { visit_id: id, user_id: crew[n % 10].id, business_id: @business.id, created_at: Time.current, updated_at: Time.current } })
    end
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) } # cached ones count too
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { week }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_response :success
    assert_select "#schedule-grid [id^=cal-visit-]", 203
    assert_operator queries, :<, 40, "queries don't grow with the number of visits"
    assert_operator elapsed, :<, 3, "rendered in #{elapsed.round(2)} s"
  end
end
