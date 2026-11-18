require "test_helper"

# JOB-02: scheduling, moving, reassigning, cancelling and finishing visits from the job page.
class Admin::VisitsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @tech = member_with_role(:technician)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: maria, title: "Spring cleanup")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def schedule(**fields)
    post admin_job_visits_path(@job), params: { visit: { scheduled_on: "2026-11-24", timing: "window", start_time: "08:00", window_end_time: "10:00",
                                                           duration_hours: "2", assignee_ids: [ "", @tech.id ], instructions: "Gate code 4417" }.merge(fields) }
  end

  def visits = as_business(@business) { @job.visits.in_order.to_a }

  test "only Owners and Admins schedule, and another business's jobs and visits aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_job_visit_path(@job) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { schedule }
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      job = Job.create!(client:, title: "Theirs")
      job.visits.new(scheduled_on: Date.new(2026, 11, 24)).schedule!(by: nil)
    end
    assert_not_found_across_businesses { get new_admin_job_visit_path(theirs.job) }
    assert_not_found_across_businesses { patch cancel_admin_job_visit_path(theirs.job, theirs) }
    visit = (schedule && visits.first)
    assert_not_found_across_businesses { patch cancel_admin_job_visit_path(theirs.job, visit) }
  end

  test "scheduling a visit from the job page" do
    get admin_job_path(@job)
    assert_select "#visits a[href=?]", new_admin_job_visit_path(@job), /Schedule visit/
    get new_admin_job_visit_path(@job)
    assert_select "input#timing-window[checked]"
    assert_select "input[name='visit[duration_hours]'][value='1']"
    assert_select "input[name='visit[assignee_ids][]'][value=?]", @tech.id.to_s

    schedule
    assert_redirected_to admin_job_path(@job)
    visit = visits.sole
    assert_equal [ Date.new(2026, 11, 24), Time.utc(2026, 11, 24, 13), 120, [ @tech ], "Gate code 4417", users(:one) ],
                 [ visit.scheduled_on, visit.starts_at, visit.duration_minutes, as_business(@business) { visit.assignees.to_a }, visit.instructions, visit.created_by ]
    assert_equal "scheduled", @job.reload.status
    follow_redirect!
    assert_select "#visit-#{visit.uid}", /Tuesday, arrive 8–10 am.*About 2 h.*#{@tech.full_name}.*Gate code 4417/m
  end

  test "mistakes are shown on the form" do
    schedule(window_end_time: "07:00", duration_hours: "0")
    assert_response :unprocessable_content
    assert_select ".error-text", /must be after the window starts/
    assert_select ".error-text", /between 5 minutes and 24 hours/
    assert_empty visits
  end

  test "rescheduling and reassigning, with the history" do
    schedule
    visit = visits.sole
    patch admin_job_visit_path(@job, visit), params: { visit: { scheduled_on: "2026-11-26", timing: "exact", start_time: "13:00", assignee_ids: [ "" ], lock_version: visit.lock_version } }
    assert_redirected_to admin_job_path(@job)
    visit.reload
    assert_equal [ Date.new(2026, 11, 26), "exact", Time.utc(2026, 11, 26, 18) ], [ visit.scheduled_on, visit.timing, visit.starts_at ]
    assert_empty as_business(@business) { visit.assignees.to_a }
    get admin_job_path(@job)
    assert_select "#visit-#{visit.uid} details", /Moved from Tue, Nov 24 · Arrive 8–10 am to Thu, Nov 26 · 1 pm.*Removed #{@tech.full_name}/m

    patch admin_job_visit_path(@job, visit), params: { visit: { scheduled_on: "2026-11-27", lock_version: 0 } }
    assert_redirected_to edit_admin_job_visit_path(@job, visit)
    assert_match "changed in another tab", flash[:alert]
  end

  test "cancel, restore, and mark done" do
    schedule
    visit = visits.sole
    patch cancel_admin_job_visit_path(@job, visit), params: { reason: "Rain" }
    assert_equal [ "cancelled", "Rain", "unscheduled" ], [ visit.reload.status, visit.cancel_reason, @job.reload.status ]
    patch restore_admin_job_visit_path(@job, visit)
    assert_equal "scheduled", visit.reload.status
    patch complete_admin_job_visit_path(@job, visit)
    assert_equal [ "completed", "in_progress" ], [ visit.reload.status, @job.reload.status ]
    patch cancel_admin_job_visit_path(@job, visit)
    assert_match "already done", flash[:alert]
  end

  test "the job list offers to schedule jobs that need it" do
    get admin_jobs_path(filter: "unscheduled")
    assert_select "#job-#{@job.uid} a[href=?]", new_admin_job_visit_path(@job), "Schedule"
    as_business(@business) { @job.complete!(by: nil) }
    post admin_job_visits_path(@job), params: { visit: { scheduled_on: "2026-11-24", timing: "anytime" } }
    assert_match "Reopen it to schedule visits", flash[:alert]
  end
end
