require "test_helper"

# JOB-05: the client's visit page from their email link, and staff's side: a note for the
# client, "Email the client about this", and the emails listed on the job.
class ClientVisitEmailsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", phone: "555-380-0000", email: "office@oakline.example")
    @owner = users(:one)
    as_business(@business) do
      @client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ],
                               properties_attributes: [ { address_line1: "12 Elm St", city: "Asheville", region: "NC", postal_code: "28801" } ])
      @job = Job.create!(client: @client, property: @client.properties.first, title: "Spring cleanup", instructions: "Gate code 4417")
    end
    @day = @business.today + 7
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def schedule(**fields)
    post admin_job_visits_path(@job), params: { visit: { scheduled_on: @day.iso8601, timing: "window", start_time: "08:00", window_end_time: "10:00", duration_hours: "2",
                                                           instructions: "Bag the leaves", client_note: "Please leave the side gate unlocked." }, **fields }
  end

  def settle = travel(Job::CLIENT_NOTICE_DELAY + 1.second) { perform_enqueued_jobs(only: VisitClientNoticeJob); perform_enqueued_jobs(only: ClientMailDeliveryJob) }

  test "the client's email and page: when, where, the note for them and how to reach the business; never the crew's instructions" do
    get new_admin_job_visit_path(@job)
    assert_select "textarea[name='visit[client_note]']"
    assert_select "input[type=checkbox][name=notify_client][checked]"
    assert_select "label", text: /Email Maria Lopez about this.*To maria@example.com/m

    schedule
    settle
    mail = ActionMailer::Base.deliveries.last
    html, text = mail.html_part.body.to_s, mail.text_part.body.to_s
    assert_equal [ "maria@example.com" ], mail.to
    assert_includes text, "Your visit is booked."
    assert_includes text, "Please leave the side gate unlocked."
    assert_includes text, "12 Elm St"
    assert_not_includes html + text, "Bag the leaves"
    assert_not_includes html + text, "Gate code"

    link = text[%r{http://[^ \n]+/c/\w+}]
    sign_out :user
    get URI(link).path
    assert_response :success
    assert_select "h1", @day.strftime("%A, %B %-d")
    assert_select "main", text: /Arrive 8–10 am.*Spring cleanup.*12 Elm St.*Please leave the side gate unlocked/m
    assert_select "a[href='tel:555-380-0000']"
    assert_select "main", text: /Bag the leaves|Gate code/, count: 0

    visit = as_business(@business) { @job.visits.first }
    as_business(@business) { visit.cancel!(by: @owner) }
    get URI(link).path
    assert_select ".banner", text: /This visit is cancelled/
  end

  test "untick \"Email the client\" and they aren't told; the job lists what was sent and what's pending" do
    schedule(notify_client: "0")
    assert_no_enqueued_jobs(only: VisitClientNoticeJob)
    get admin_job_path(@job)
    assert_select "#client-emails", 0
    assert_select "dialog[id^=visit-cancel-] input[type=checkbox][name=notify_client]", 1, "cancelling asks too"

    visit = as_business(@business) { @job.visits.first }
    patch cancel_admin_job_visit_path(@job, visit), params: { reason: "Rain" }
    get admin_job_path(@job)
    assert_select "#client-emails", text: /Your latest changes go out at.*Pending/m

    patch restore_admin_job_visit_path(@job, visit)
    settle
    get admin_job_path(@job)
    assert_select "#client-emails", 0, "cancelled then restored before it went: nothing to say"
  end

  test "the job page lists the emails sent, with how they went" do
    schedule
    settle
    get admin_job_path(@job)
    assert_select "#client-emails li", text: /Visit booked: .*To maria@example.com.*Sent/m
  end
end
