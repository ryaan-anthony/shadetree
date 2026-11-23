require "test_helper"

# ACC-09: staff see photos (or initials) and titles on the Team page, on visit assignees in the
# schedule and on job pages, and on My day (the person and their crew-mates). Lists stay fast:
# the photos are loaded once, not per person.
class Admin::TeamFacesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @tech = member_with_role(:technician)
    @crew_mate = member_with_role(:technician)
    @business.business_users.find_by!(user: @tech).update!(photo: Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg"), title: "Lead technician")
    as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @job = Job.create!(client:, title: "Spring cleanup")
      @visit = @job.visits.new(scheduled_on: @business.today, timing: "exact", start_time: "09:00", duration_minutes: 60, assignee_ids: [ @tech.id, @crew_mate.id ])
      @visit.schedule!(by: @owner, notify_client: false)
    end
  end

  def as_member(user)
    sign_in user
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def queries(path)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path }
    assert_response :success
    count
  end

  test "the Team page shows each member's photo or initials and title" do
    as_member(@owner)
    get admin_team_path
    tech = @business.business_users.find_by!(user: @tech)
    assert_select "#member-#{tech.uid} img.avatar[alt='']"
    assert_select "#member-#{tech.uid} .sub", /Lead technician · #{@tech.email}/
    assert_select "#member-#{business_users(:one).uid} span.avatar", "JD"
  end

  test "the schedule's visit panel and the job page show the crew with faces and titles" do
    as_member(@owner)
    get admin_schedule_visit_path(@visit)
    assert_select "dd ul li", 2
    assert_select "dd li", /#{@tech.full_name}\s*Lead technician/
    get admin_job_path(@job)
    assert_select "#visit-#{@visit.uid} li img.avatar"
    assert_select "#visit-#{@visit.uid} li", /#{@crew_mate.full_name}/
  end

  test "My day shows the person and their crew-mates on each visit" do
    as_member(@crew_mate)
    get admin_my_day_path
    assert_select "#my-visit-#{@visit.uid} .avatar", 2
    assert_select "#my-visit-#{@visit.uid}", /With #{@tech.first_name}/
    get admin_my_visit_path(@visit)
    assert_select "li", /#{@tech.full_name}\s*Lead technician/
  end

  test "more people on the team don't mean more queries" do
    as_member(@owner)
    get admin_team_path
    get admin_schedule_path
    before = [ queries(admin_team_path), queries(admin_schedule_path) ]
    3.times do
      user = member_with_role(:technician)
      @business.business_users.find_by!(user:).update!(photo: Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg"), title: "Tech")
    end
    after = [ queries(admin_team_path), queries(admin_schedule_path) ]
    assert_operator before.min, :>, 5
    assert_operator after[0], :<=, before[0] + 1, "Team page"
    assert_operator after[1], :<=, before[1] + 1, "schedule"
  end
end
