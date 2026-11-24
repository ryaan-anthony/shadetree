require "test_helper"

# JOB-05: what clients are told about their visits, and when: one email per settled burst of
# changes to a job's visits, nothing for changes that cancel out, nothing when staff say not to.
class VisitClientNoticeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # A fixed day: a week on from late December, the labels below would carry the next year.
    travel_to Time.utc(2026, 11, 24, 15)
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    Current.business = @business
    @client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ],
                             properties_attributes: [ { address_line1: "12 Elm St", city: "Asheville", region: "NC", postal_code: "28801" } ])
    @job = Job.create!(client: @client, property: @client.properties.first, title: "Spring cleanup")
    @day = @business.today + 7
  end

  teardown { Current.reset }

  def book(on = @day, notify_client: true, **fields)
    @job.visits.new(scheduled_on: on, timing: "window", start_time: "08:00", window_end_time: "10:00", **fields).tap { _1.schedule!(by: @owner, notify_client:) }
  end

  # What a few minutes later would send.
  def settle
    travel(Job::CLIENT_NOTICE_DELAY + 1.second) do
      perform_enqueued_jobs(only: [ VisitClientNoticeJob, ClientMailDeliveryJob ])
      perform_enqueued_jobs(only: ClientMailDeliveryJob)
    end
  end

  def emails = EmailMessage.where(related: @job).order(:id).to_a
  def mails = ActionMailer::Base.deliveries

  test "a booking is emailed a few minutes later, once, to the client's email" do
    assert_enqueued_with(job: VisitClientNoticeJob, args: [ @business.id, @job.id ]) { book }
    assert @job.reload.client_notice_due_at
    assert_no_difference("EmailMessage.count", "not straight away") { VisitClientNotice.deliver_due(@job.reload) }

    settle
    assert_equal [ [ "visit_scheduled", "maria@example.com", "sent" ] ], emails.map { [ _1.kind, _1.to, _1.status ] }
    assert_equal "Visit booked: #{@job.visits.first.when_label}", mails.last.subject
    assert_nil @job.reload.client_notice_due_at
    assert @job.visits.first.client_up_to_date?
    assert_no_difference("EmailMessage.count", "nothing new to say") { settle }
  end

  test "several days booked at once are one email" do
    Visit.schedule_all!((0..2).map { @job.visits.new(scheduled_on: @day + _1, timing: "anytime") }, by: @owner)
    settle
    assert_equal 1, emails.size
    assert_equal "3 visits booked, from #{@day.strftime("%b %-d")}", mails.last.subject
    assert_equal 3, mails.last.text_part.body.to_s.scan("View visit:").size
  end

  test "moves in quick succession are one email; moved and moved back is none" do
    visit = book
    settle
    visit.reload.reschedule!({ scheduled_on: @day + 1 }, by: @owner)
    visit.reload.reschedule!({ scheduled_on: @day + 2, start_time: "13:00", window_end_time: "15:00" }, by: @owner)
    settle
    assert_equal %w[visit_scheduled visit_changed], emails.map(&:kind)
    assert_match(/Was #{Regexp.escape(@day.strftime("%a, %b %-d"))} · Arrive 8–10 am/, mails.last.text_part.body.to_s)

    visit.reload.reschedule!({ scheduled_on: @day + 3 }, by: @owner)
    visit.reload.reschedule!({ scheduled_on: @day + 2 }, by: @owner)
    assert_no_difference("EmailMessage.count") { settle }
  end

  test "booked and cancelled before the email went is nothing; cancelled after it is a cancellation" do
    first = book
    first.cancel!(by: @owner)
    assert_no_difference("EmailMessage.count") { settle }

    second = book(@day + 1)
    settle
    second.cancel!(by: @owner)
    settle
    assert_equal %w[visit_scheduled visit_cancelled], emails.map(&:kind)
    assert_match "Visit cancelled", mails.last.subject

    second.restore!(by: @owner)
    settle
    assert_equal "visit_scheduled", emails.last.kind, "restored: booked again"
  end

  test "cancelling the job tells the client about its upcoming visits in one email" do
    book
    book(@day + 1)
    settle
    @job.cancel!(by: @owner, reason: "Moved away")
    settle
    assert_equal "visit_cancelled", emails.last.kind
    assert_equal "2 visits cancelled", mails.last.subject
  end

  test "\"don't email the client\" for a change: nothing goes, and it counts as what they know" do
    visit = book(notify_client: false)
    assert_no_enqueued_jobs(only: VisitClientNoticeJob)
    assert visit.reload.client_up_to_date?
    visit.reload.reschedule!({ scheduled_on: @day + 1 }, by: @owner, notify_client: false)
    visit.reload.cancel!(by: @owner, notify_client: false)
    assert_no_difference("EmailMessage.count") { settle }
  end

  test "no email address, a type turned off, or a visit already past: nothing is sent, and they're up to date" do
    @client.contact_methods.destroy_all
    visit = book
    assert_no_difference("EmailMessage.count") { settle }
    assert visit.reload.client_up_to_date?

    @client.contact_methods.create!(kind: "email", value: "maria@example.com")
    @business.update!(client_visit_emails: { "changed" => false })
    visit.reload.reschedule!({ scheduled_on: @day + 1 }, by: @owner)
    assert_no_difference("EmailMessage.count") { settle }

    past = book(@business.today - 1)
    assert_no_difference("EmailMessage.count") { settle }
    assert_nil past.reload.client_told, "past visits aren't news"
  end

  test "unticked after an email is already due: that email still goes, with the visit as it is now" do
    visit = book
    visit.reload.reschedule!({ scheduled_on: @day + 1 }, by: @owner, notify_client: false)
    settle
    assert_equal %w[visit_scheduled], emails.map(&:kind)
    assert_match "Visit booked: #{(@day + 1).strftime("%a, %b %-d")}", mails.last.subject
  end

  test "anytime and exact-time visits are up to date once told" do
    anytime = book(timing: "anytime", start_time: nil, window_end_time: nil)
    exact = book(@day + 1, timing: "exact", start_time: "09:00", window_end_time: nil)
    settle
    assert [ anytime, exact ].all? { _1.reload.client_up_to_date? }
    book(@day + 2)
    settle
    assert_equal %w[visit_scheduled visit_scheduled], emails.map(&:kind), "the second email is only about the new visit"
    assert_equal 1, mails.last.text_part.body.to_s.scan("View visit:").size
  end

  test "someone who hasn't confirmed their email can't email clients; the hourly limit postpones, never drops" do
    unconfirmed = users(:unconfirmed)
    visit = @job.visits.new(scheduled_on: @day, timing: "anytime").tap { _1.schedule!(by: unconfirmed) }
    assert_nil @job.reload.client_notice_due_at
    assert visit.reload.client_up_to_date?

    book(@day + 1)
    EmailMessage::CLIENT_EMAILS_PER_HOUR.times { EmailMessage.create!(kind: "quote_sent", to: "someone@example.com") }
    settle
    assert_empty emails
    assert_operator @job.reload.client_notice_due_at, :>, Time.current
    travel(1.hour + VisitClientNotice::HOURLY_LIMIT_WAIT) { perform_enqueued_jobs(only: VisitClientNoticeJob) }
    assert_equal %w[visit_scheduled], emails.map(&:kind)
  end

  test "completing a job doesn't email about the visits it cancels" do
    book
    settle
    @job.complete!(by: @owner)
    assert_no_difference("EmailMessage.count") { settle }
  end

  test "the email shows the visit as it was decided, even if it changes before delivery" do
    visit = book
    travel(Job::CLIENT_NOTICE_DELAY + 1.second) { perform_enqueued_jobs(only: VisitClientNoticeJob) }
    visit.reload.reschedule!({ scheduled_on: @day + 3 }, by: @owner, notify_client: false)
    perform_enqueued_jobs(only: ClientMailDeliveryJob)
    assert_match "Visit booked: #{@day.strftime("%a, %b %-d")}", mails.last.subject
  end

  test "a job from another business isn't touched" do
    theirs = Tenancy.with_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "email", value: "them@example.com" } ])
      Job.create!(client:, title: "Theirs").tap { |job| job.visits.new(scheduled_on: @day, timing: "anytime").schedule!(by: nil) }
    end
    Current.reset
    VisitClientNoticeJob.perform_now(@business.id, theirs.id)
    Tenancy.with_business(businesses(:two)) { assert theirs.reload.client_notice_due_at, "still pending in its own business" }
    Current.business = @business
  end

  test "a visit's client link is kept, and lasts until a month after the visit wherever it moves" do
    visit = book
    link = visit.client_link!
    assert_equal link, visit.client_link!
    visit.reload.reschedule!({ scheduled_on: @day + 60 }, by: @owner)
    assert_equal link, visit.reload.client_link!
    assert_operator link.reload.expires_at, :>, @business.local_time(@day + 89, "12:00")
  end
end
