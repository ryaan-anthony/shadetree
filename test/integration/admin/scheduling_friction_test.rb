require "test_helper"

# #289 (admin UX review), scheduling friction: a one-person crew is already ticked, an empty
# week points to the next visit, and finished jobs are one tap away.
class Admin::SchedulingFrictionTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: @maria, title: "Ants")
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def ticked = css_select("input[name='visit[assignee_ids][]'][type=checkbox][checked]").map { _1["value"].to_i }

  test "the only person who works visits is ticked; with a crew, nobody is, unless a slot chose them" do
    get new_admin_job_visit_path(@job)
    assert_equal [ @owner.id ], ticked, "a one-person business doesn't have to tick themselves"

    tech = member_with_role(:technician)
    get new_admin_job_visit_path(@job)
    assert_empty ticked, "with two people, the office chooses"
    get new_admin_job_visit_path(@job, crew: tech.id)
    assert_equal [ tech.id ], ticked, "a slot in someone's row still chooses them"
  end

  def book(on, **attributes)
    as_business(@business) do
      @job.visits.create!(scheduled_on: on, timing: "window", start_time: "08:00", window_end_time: "10:00", duration_minutes: 45, **attributes)
          .tap { @job.update_columns(status: "scheduled") }
    end
  end

  test "an empty week points to the next open visit, for the same people, from today on" do
    travel_to Time.utc(2026, 11, 18, 15) do
      done = book(Date.new(2026, 11, 23))
      as_business(@business) { done.update_columns(status: "completed") }
      tech = member_with_role(:technician)
      unassigned = book(Date.new(2026, 11, 30))
      book(Date.new(2026, 11, 10)) # still open, but in the past
      mine = book(Date.new(2026, 12, 7)).tap { |v| as_business(@business) { v.assignments.create!(business: @business, user: tech) } }

      get admin_schedule_path(date: "2026-11-18")
      assert_select "#next-visit a[href*='date=2026-11-30']", "Next visit: Mon, Nov 30", "a done visit doesn't count"
      get admin_schedule_path(date: "2026-11-18", member: tech.id)
      assert_select "#next-visit a[href*='date=2026-12-07']", "Next visit: Mon, Dec 7", "the same person's next visit"
      get admin_schedule_path(date: "2026-11-18", member: "unassigned")
      assert_select "#next-visit a[href*='date=2026-11-30']"
      get admin_schedule_path(date: "2026-11-02")
      assert_select "#next-visit a[href*='date=2026-11-30']", 1, "from a past week: the next one from today, not Nov 10"
      get admin_schedule_path(date: "2026-11-30")
      assert_select "#next-visit", 0, "the week with the visit doesn't point elsewhere"
      assert_select "#nothing-to-book", /No jobs are waiting for a visit/
      assert mine && unassigned
    end
  end

  test "an empty week whose next booking is a request follow-up points to it (JOB-07)" do
    travel_to Time.utc(2026, 11, 18, 15) do
      request = as_business(@business) { ServiceRequest.create!(client: @maria, source: "phone", description: "Ants") }
      as_business(@business) { RequestFollowUp.assign!(request, { user: @owner, kind: "call", scheduled_on: Date.new(2026, 11, 25) }, by: @owner) }
      book(Date.new(2026, 12, 2))
      get admin_schedule_path(date: "2026-11-16")
      assert_select "#next-visit a[href*='date=2026-11-25']", "Next follow-up: Wed, Nov 25"
      get admin_schedule_path(date: "2026-11-23")
      assert_select "#next-visit", 0, "the week with the follow-up isn't empty"
    end
  end

  test "when nothing is left to do, the jobs list offers the completed ones" do
    as_business(@business) { @job.update_columns(status: "completed", completed_at: Time.current) }
    get admin_jobs_path
    assert_select "h2", "Nothing to do"
    assert_select "a#show-completed[href=?]", admin_jobs_path(filter: "completed"), "Show 1 completed job"
  end
end
