require "test_helper"

# JOB-12: the "On my way" email and its update: fixed wording, branded with a plain-text part,
# the photo inside the email, first names only, phones, the business's wording (NTF-03), and
# that it's listed on the job.
class VisitOnTheWayMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper
  include PermissionHelpers

  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", show_team_profiles: true, client_visit_emails: { "on_my_way" => "1" }, phone: "555-0100",
                      plan_overrides: { "limits" => { "team_members" => nil } })
    @marcus = member_with_role(:technician).tap { _1.update!(first_name: "Marcus", last_name: "Reed") }
    @dee = member_with_role(:technician).tap { _1.update!(first_name: "Dee", last_name: "Park") }
    @business.business_users.find_by!(user: @marcus).update!(photo: Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg"),
                                                             title: "Lead technician", work_phone: "555-0199")
    travel_to zone.parse("2026-12-10 10:45")
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", billing: true } ])
      @job = Job.create!(client:, property: client.properties.first, title: "Spring cleanup")
      @visit = @job.visits.new(scheduled_on: Date.new(2026, 12, 10), timing: "window", start_time: "09:00", window_end_time: "12:00", assignee_ids: [ @marcus.id, @dee.id ])
                   .tap { _1.schedule!(by: users(:one), notify_client: false) }
    end
  end

  teardown { travel_back }

  def zone = ActiveSupport::TimeZone["America/New_York"]

  def send!(minutes, by: @marcus)
    Tenancy.with_business(@business) { @visit.reload.send_on_the_way!(@visit.on_the_way_arrival(minutes:), by:) }
    perform_enqueued_jobs(only: ClientMailDeliveryJob)
    ActionMailer::Base.deliveries.last
  end

  test "the example: Marcus is on the way, arriving about 11:15 am, with his photo inside the email and no last name" do
    mail = send!(30)
    assert_equal [ "maria@example.com" ], mail.to
    assert_equal "Marcus and Dee are on the way, arriving about 11:15 am", mail.subject
    html, text = mail.html_part.body.decoded, mail.text_part.body.decoded
    assert_match "Marcus and Dee are on the way, arriving about 11:15 am.", html
    assert_match "Thu, Dec 10 · Arrive 9 am–12 pm", text
    assert_match "12 Elm St, Austin", text
    assert_match "Marcus - Lead technician - 555-0199", text
    assert_match "Need to reach us? Call 555-0100.", text, "Dee has no work phone: the business's, once"
    assert_no_match(/Reed|Park|technician-/, html + text, "no last name or email")
    photo = mail.attachments.find { _1.filename.start_with?("team-") }
    assert photo&.inline?, "the photo travels inside the email"
    assert_match %(src="cid:#{photo.cid}"), html
    assert_no_match %r{/rails/active_storage}, html, "never a link to the stored photo"
    assert_match %r{/c/[\w-]+}, text, "the button to their visit page"
    message = Tenancy.with_business(@business) { @job.email_messages.sole }
    assert_equal [ "visit_on_the_way", "sent" ], [ message.kind, message.status ]
  end

  test "an update 10+ minutes off is the Updated arrival time email; a small one sends none" do
    send!(30)
    travel_to(zone.parse("2026-12-10 10:47")) { send!(30) } # 11:15 again: no email
    assert_equal 1, ActionMailer::Base.deliveries.size
    travel_to(zone.parse("2026-12-10 10:55")) { assert_equal "Updated arrival time: about 11:40 am", send!(45, by: @dee).subject }
    assert_match "Dee and Marcus are on the way, arriving about 11:40 am", ActionMailer::Base.deliveries.last.text_part.body.decoded
  end

  test "profiles off: the business's name and its phone, no people" do
    @business.update!(show_team_profiles: false)
    mail = send!(30)
    assert_equal "#{@business.name} is on the way, arriving about 11:15 am", mail.subject
    assert_no_match(/Marcus|Lead technician/, mail.text_part.body.decoded)
    assert_empty mail.attachments.select { _1.filename.start_with?("team-") }
  end

  test "the business's own subject and opening (NTF-03)" do
    Tenancy.with_business(@business) do
      MessageTemplate.create!(kind: "visit_on_the_way", subject: "{{business_name}}: {{on_the_way}}", body: "Hello {{client_first_name}}, see you {{arrival_time}}.")
    end
    mail = send!(30)
    assert_equal "#{@business.name}: Marcus and Dee are on the way", mail.subject
    assert_match "Hello Maria, see you about 11:15 am.", mail.text_part.body.decoded
    assert_match "Marcus and Dee are on the way, arriving about 11:15 am.", mail.text_part.body.decoded, "the fixed wording stays"
  end

  test "started before it went: not sent" do
    Tenancy.with_business(@business) { @visit.send_on_the_way!(@visit.on_the_way_arrival(minutes: 30), by: @marcus) }
    Tenancy.with_business(@business) { @visit.reload.start!(by: @marcus) }
    perform_enqueued_jobs(only: ClientMailDeliveryJob)
    assert_empty ActionMailer::Base.deliveries
    assert_equal "failed", Tenancy.with_business(@business) { @job.email_messages.sole.status }
  end
end
