require "test_helper"

# JOB-02: the form shows warnings before booking, books several days at once, and the people
# going choose how they hear about it.
class Admin::VisitWarningsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @tech = member_with_role(:technician)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: maria, title: "Spring cleanup")
      Closure.create!(reason: "Thanksgiving", starts_on: Date.new(2026, 11, 26))
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def visit_fields(**fields) = { scheduled_on: "2026-11-24", timing: "exact", start_time: "09:00", duration_hours: "2", assignee_ids: [ "", @tech.id ] }.merge(fields)
  def visits = as_business(@business) { @job.visits.in_order.to_a }

  test "a warning comes back to the form first, then Schedule anyway books it" do
    post admin_job_visits_path(@job), params: { visit: visit_fields(scheduled_on: "2026-11-26") }
    assert_response :unprocessable_content
    assert_select ".banner-warning li", "You're closed for Thanksgiving."
    assert_select "input[type=hidden][name=confirm][value='1']"
    assert_select "input[type=submit][value='Schedule anyway']"
    assert_empty visits

    post admin_job_visits_path(@job), params: { visit: visit_fields(scheduled_on: "2026-11-26"), confirm: "1" }
    assert_redirected_to admin_job_path(@job)
    assert_equal [ Date.new(2026, 11, 26) ], visits.map(&:scheduled_on)
  end

  test "no warnings, no extra step" do
    post admin_job_visits_path(@job), params: { visit: visit_fields }
    assert_redirected_to admin_job_path(@job)
  end

  test "several days from the form: a range skipping closed days, plus a day picked on its own" do
    get new_admin_job_visit_path(@job)
    assert_select "details summary", "More than one day"
    assert_select "input[name=through]"
    assert_select "input#skip_closed[checked]"

    post admin_job_visits_path(@job), params: { visit: visit_fields(scheduled_on: "2026-11-25"), through: "2026-11-30", skip_closed: "1", extra_dates: [ "2026-12-02", "" ] }
    assert_redirected_to admin_job_path(@job)
    assert_equal [ "Wed, Nov 25", "Fri, Nov 27", "Mon, Nov 30", "Wed, Dec 2" ], visits.map { _1.scheduled_on.strftime("%a, %b %-d") }, "Thanksgiving and the weekend skipped"
    assert_equal "4 visits scheduled, Nov 25 to Dec 2.", flash[:notice]
    assert visits.all? { _1.starts_at.in_time_zone(@business.time_zone).hour == 9 }

    post admin_job_visits_path(@job), params: { visit: visit_fields(scheduled_on: "2026-01-01"), through: "2026-12-31", skip_closed: "0" }
    assert_response :unprocessable_content
    assert_select ".banner-danger", /more than #{Visit::MAX_DAYS} days/
  end

  test "editing warns only when the time or crew changes" do
    post admin_job_visits_path(@job), params: { visit: visit_fields(start_time: "16:00"), confirm: "1" }
    visit = visits.sole
    patch admin_job_visit_path(@job, visit), params: { visit: { instructions: "Bring the ladder", lock_version: visit.lock_version } }
    assert_redirected_to admin_job_path(@job), "already outside hours, but only the instructions changed"
    patch admin_job_visit_path(@job, visit), params: { visit: { start_time: "16:30", lock_version: visit.reload.lock_version } }
    assert_response :unprocessable_content
    assert_select ".banner-warning li", /outside your hours/
    assert_select "input[type=submit][value='Save anyway']"
  end

  test "technicians choose how they hear about their visits" do
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    get settings_admin_notifications_path
    assert_select "input[name='email[]'][value=visit_assigned][checked]"
    assert_select "input[name='email[]'][value=visit_cancelled][checked]"
    assert_select "input[name='email[]'][value=quote_approved]", 0
  end
end
