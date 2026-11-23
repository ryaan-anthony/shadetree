require "test_helper"

# JOB-12: the "On the way" card on the client's visit page: who and when, their photos through
# the visit's link (ACC-09), "any minute" for an hour past the time, and gone once the visit
# starts, ends or moves. Also the staff labels on the schedule and the job.
class Client::OnTheWayCardTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", show_team_profiles: true, client_visit_emails: { "on_my_way" => "1" },
                      plan_overrides: { "limits" => { "team_members" => nil } })
    @marcus = member_with_role(:technician).tap { _1.update!(first_name: "Marcus", last_name: "Reyes") }
    @dee = member_with_role(:technician).tap { _1.update!(first_name: "Dee", last_name: "Okafor") }
    @other = member_with_role(:technician)
    [ @marcus, @other ].each { membership(_1).update!(photo: Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg"), title: "Lead technician") }
    travel_to zone.parse("2026-12-10 10:45")
    as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @job = Job.create!(client:, title: "Spring cleanup")
      @visit = @job.visits.new(scheduled_on: Date.new(2026, 12, 10), timing: "window", start_time: "09:00", window_end_time: "12:00", assignee_ids: [ @marcus.id, @dee.id ])
                   .tap { _1.schedule!(by: users(:one), notify_client: false) }
      @token = @visit.client_link!.token
    end
  end

  teardown { travel_back }

  def zone = ActiveSupport::TimeZone["America/New_York"]
  def membership(user) = @business.business_users.find_by!(user:)
  def send!(minutes = 30, by: @marcus) = as_business(@business) { @visit.reload.send_on_the_way!(@visit.on_the_way_arrival(minutes:), by:) }

  test "none until someone's on the way; then who, when, photo, first name and title only" do
    get client_link_path(@token)
    assert_select "#on-the-way", 0
    send!
    get client_link_path(@token)
    assert_select "#on-the-way h2", "Marcus and Dee are on the way, arriving about 11:15 am"
    assert_select "#on-the-way img[alt=''][src=?]", client_team_photo_path(@token, membership(@marcus).uid)
    assert_select "#on-the-way", /Lead technician/
    assert_select "#on-the-way span.avatar", "D"
    assert_no_match(/Reyes|Okafor/, response.body)
    get client_team_photo_path(@token, membership(@marcus).uid)
    assert_response :redirect, "the card's photo loads through the link"
    get client_team_photo_path(@token, membership(@other).uid)
    assert_response :not_found, "someone not on the card"
  end

  test "past the time it's any minute for an hour, then it goes" do
    send!
    travel_to(zone.parse("2026-12-10 11:20")) do
      get client_link_path(@token)
      assert_select "#on-the-way h2", "Marcus and Dee should be with you any minute"
    end
    travel_to(zone.parse("2026-12-10 12:16")) do
      get client_link_path(@token)
      assert_select "#on-the-way", 0
      get client_team_photo_path(@token, membership(@marcus).uid)
      assert_response :not_found
    end
  end

  test "profiles off, or the sender deactivated: the business's name and no one's photo" do
    send!
    @business.update!(show_team_profiles: false)
    get client_link_path(@token)
    assert_select "#on-the-way h2", "#{@business.name} is on the way, arriving about 11:15 am"
    assert_select "#on-the-way img", 0
    @business.update!(show_team_profiles: true)
    membership(@marcus).update!(active: false)
    get client_link_path(@token)
    assert_select "#on-the-way h2", "#{@business.name} is on the way, arriving about 11:15 am"
  end

  test "starting, cancelling or moving the visit removes the card with no extra email" do
    send!
    as_business(@business) { @visit.reload.reschedule!({ start_time: "13:00", window_end_time: "15:00" }, by: users(:one), notify_client: false) }
    get client_link_path(@token)
    assert_select "#on-the-way", 0
    travel(2.minutes) { send! }
    as_business(@business) { @visit.reload.cancel!(by: users(:one), notify_client: false) }
    get client_link_path(@token)
    assert_select "#on-the-way", 0
    assert_equal 2, as_business(@business) { @job.email_messages.count }, "the two sends' emails, nothing more"
  end

  test "staff see On the way on the job and the schedule" do
    send!
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_job_path(@job)
    assert_select "#visit-#{@visit.uid} .badge", /On the way · about 11:15 am/
    assert_select "#visit-#{@visit.uid} details li", /On the way, arriving about 11:15 am \(emailed\).*Marcus Reyes/m
    get admin_schedule_path(view: "day", date: "2026-12-10")
    assert_select "#schedule-agenda", /On the way · about 11:15 am/
    assert_select ".cal-visit", /On the way/
    get admin_schedule_visit_path(@visit)
    assert_select "dd", "On the way · about 11:15 am"
  end
end
