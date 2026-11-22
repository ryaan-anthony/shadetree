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

  test "an empty week says nothing is waiting and points to the next visit" do
    travel_to Time.utc(2026, 11, 18, 15) do
      as_business(@business) { @job.visits.create!(scheduled_on: Date.new(2026, 11, 23), timing: "window", start_time: "08:00", window_end_time: "10:00", duration_minutes: 45) && @job.update_columns(status: "scheduled") }
      get admin_schedule_path(date: "2026-11-18")
      assert_select "#nothing-to-book", /No jobs are waiting for a visit\.\s*Next visit: Mon, Nov 23/
      assert_select "#nothing-to-book a[href*='date=2026-11-23']"
      get admin_schedule_path(date: "2026-11-23")
      assert_select "#nothing-to-book a", 0, "the week with the visit doesn't point elsewhere"
    end
  end

  test "when nothing is left to do, the jobs list offers the completed ones" do
    as_business(@business) { @job.update_columns(status: "completed", completed_at: Time.current) }
    get admin_jobs_path
    assert_select "h2", "Nothing to do"
    assert_select "a#show-completed[href=?]", admin_jobs_path(filter: "completed"), "Show 1 completed job"
  end
end
