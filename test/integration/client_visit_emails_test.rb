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
    assert_includes html, %(color:#{@business.branding.link_color};">View visit), "link text in the readable brand shade (owner, 2026-11-21)"

    link = text[%r{http://[^ \n]+/c/\w+}]
    sign_out :user
    get URI(link).path
    assert_response :success
    assert_select "h1", @day.strftime("%A, %B %-d")
    assert_select "main", text: /Arrive 8–10 am.*Spring cleanup.*12 Elm St.*Please leave the side gate unlocked/m
    assert_select "a[href='tel:+15553800000']"
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
    assert_select "#client-emails", text: /We'll email .* at .*several changes arrive as one email.*Waiting/m

    patch restore_admin_job_visit_path(@job, visit)
    settle
    get admin_job_path(@job)
    assert_select "#client-emails", 0, "cancelled then restored before it went: nothing to say"
  end

  test "someone who hasn't confirmed their email is told why the client won't be emailed" do
    users(:one).update_columns(confirmed_at: nil)
    get new_admin_job_visit_path(@job)
    assert_select "input[name=notify_client]", 0
    assert_select "p", text: /Confirm your email address to email Maria Lopez about visits/
  end

  test "the job page lists the emails sent, with how they went" do
    schedule
    settle
    get admin_job_path(@job)
    assert_select "#client-emails li", text: /Visit booked: .*To maria@example.com.*Sent/m
  end

  test "Settings → Messages turns each kind of visit email on or off (moved there, owner, 2026-11-22)" do
    get edit_admin_business_path(tab: "documents")
    assert_select "input[name^='business[client_visit_emails]']", 0, "no longer under Quotes, jobs & invoices"
    get admin_message_templates_path
    assert_select "form#visit-emails-form[action=?]", admin_business_path(tab: "messages")
    assert_select "input[type=checkbox][name='business[client_visit_emails][reminder]'][checked]"
    assert_select "label[for=client-visit-email-scheduled]", /Visit booked/
    patch admin_business_path(tab: "messages"), params: { business: { client_visit_emails: { scheduled: "0", changed: "1", cancelled: "1", reminder: "0" } } }
    assert_redirected_to admin_message_templates_path
    assert_equal "Visit emails saved.", flash[:notice]
    follow_redirect!
    assert_select "input[type=checkbox][name='business[client_visit_emails][scheduled]']:not([checked])"
    assert_equal({ "scheduled" => false, "changed" => true, "cancelled" => true, "reminder" => false }, @business.reload.client_visit_emails)
    @business.update!(client_visit_emails: { cancelled: "0" })
    assert_equal({ "scheduled" => false, "changed" => true, "cancelled" => false, "reminder" => false }, @business.reload.client_visit_emails, "kinds not given keep their setting")

    get new_admin_job_visit_path(@job)
    assert_select "input[name=notify_client]", 0, "booking emails are off: nothing to skip"
    schedule
    settle
    assert_empty ActionMailer::Base.deliveries
    assert as_business(@business) { @job.visits.first.client_up_to_date? }, "and the client isn't told later, as if it were news"

    sign_out :user
    sign_in member_with_role(:technician)
    post switch_admin_business_path, params: { business: @business.uid }
    patch admin_business_path(tab: "messages"), params: { business: { client_visit_emails: { scheduled: "1" } } }
    assert_response :forbidden
  end

  test "the Quotes, jobs & invoices form no longer changes visit emails" do
    patch admin_business_path(tab: "documents"), params: { business: { quote_expiry_days: "30", client_visit_emails: { scheduled: "0", reminder: "0" } } }
    assert_redirected_to edit_admin_business_path(tab: "documents")
    assert @business.reload.client_visit_email?(:scheduled)
    assert @business.client_visit_email?(:reminder)
  end

  test "on Starter (templates view only) the switches still save" do
    @business.update!(plan: plans(:starter), plan_overrides: {})
    get admin_message_templates_path
    assert_select ".banner", /View only on Starter/
    assert_select "form#visit-emails-form input[type=submit][value=?]", "Save visit emails"
    patch admin_business_path(tab: "messages"), params: { business: { client_visit_emails: { changed: "0" } } }
    assert_redirected_to admin_message_templates_path
    assert_not @business.reload.client_visit_email?(:changed)
  end

  test "a business setting that needs fixing first is named, not a bare error page" do
    @business.update_columns(quote_expiry_days: 0)
    patch admin_business_path(tab: "messages"), params: { business: { client_visit_emails: { changed: "0" } } }
    assert_redirected_to admin_message_templates_path
    assert_match "Visit emails not saved:", flash[:alert]
  end

  def visit_line = css_select("#client-notice-pending").first&.text.to_s.squish

  test "the job promises an email only when one will go (#289)" do
    schedule(notify_client: "1")
    get admin_job_path(@job)
    assert_match(/We'll email Maria Lopez at .+\. We wait a few minutes/, visit_line)
    travel(Job::CLIENT_NOTICE_DELAY + 1.minute) do
      get admin_job_path(@job)
      assert_match(/We'll email Maria Lopez shortly\./, visit_line, "late: no time in the past")
    end

    # Undone before the wait ends: booked, then cancelled; the client never heard, so nothing goes.
    visit = as_business(@business) { @job.visits.sole }
    patch cancel_admin_job_visit_path(@job, visit), params: { notify_client: "1" }
    get admin_job_path(@job)
    assert_empty visit_line
  end

  test "with 'Visit booked' emails off, nothing is queued or promised (#289)" do
    @business.update!(client_visit_emails: { "scheduled" => "0" })
    schedule(notify_client: "1")
    assert_nil as_business(@business) { @job.reload.client_notice_due_at }
    get admin_job_path(@job)
    assert_empty visit_line
  end

  test "a client without an email isn't promised one (#289)" do
    as_business(@business) { @client.contact_methods.destroy_all && @client.contact_methods.create!(kind: "phone", value: "2155551212") }
    schedule(notify_client: "1")
    assert_nil as_business(@business) { @job.reload.client_notice_due_at }
    get admin_job_path(@job)
    assert_empty visit_line
  end
end
