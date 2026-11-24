require "test_helper"

# JOB-05: the day-before reminder: from 10 am the business's time, for tomorrow's visits still
# booked, once each; across time zones and clock changes.
class VisitRemindersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    Tenancy.with_business(@business) do
      @client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @job = Job.create!(client: @client, title: "Spring cleanup")
    end
  end

  def book(on, **fields)
    Tenancy.with_business(@business) do
      @job.visits.new(scheduled_on: on, timing: "window", start_time: "08:00", window_end_time: "10:00", **fields).tap { _1.schedule!(by: @owner, notify_client: false) }
    end
  end

  def at(local) = ActiveSupport::TimeZone[@business.timezone].parse(local)

  def run_hourly = VisitRemindersJob.perform_now

  def reminders = Tenancy.with_business(@business) { EmailMessage.where(kind: "visit_reminder").to_a }

  test "from 10 am the day before, once, for visits still booked" do
    visit = book(Date.new(2026, 12, 10))
    other = book(Date.new(2026, 12, 10)).tap { |v| Tenancy.with_business(@business) { v.cancel!(by: @owner, notify_client: false) } }
    travel_to(at("2026-12-09 09:59")) { run_hourly }
    assert_empty reminders, "not before 10 am"
    travel_to(at("2026-12-09 10:07")) { run_hourly }
    assert_equal 1, reminders.size
    assert_equal "maria@example.com", reminders.sole.to
    travel_to(at("2026-12-09 11:07")) { run_hourly }
    assert_equal 1, reminders.size, "once"
    assert_nil other.reload.reminder_sent_at, "a cancelled visit isn't reminded"

    travel_to(at("2026-12-09 12:00")) { Tenancy.with_business(@business) { visit.reload.reschedule!({ scheduled_on: Date.new(2026, 12, 12) }, by: @owner, notify_client: false) } }
    assert_nil visit.reload.reminder_sent_at, "moved: the new day gets its own"
    travel_to(at("2026-12-11 10:07")) { run_hourly }
    assert_equal 2, reminders.size

    travel_to(at("2026-12-11 10:08")) { perform_enqueued_jobs(only: ClientMailDeliveryJob) } # in 2026, so the date has no year
    mail = ActionMailer::Base.deliveries.last
    assert_equal "Reminder: your visit tomorrow, Sat, Dec 12 · Arrive 8–10 am", mail.subject
    assert_match %r{View visit: http://\S+/c/\w+}, mail.text_part.body.to_s
  end

  test "each business at its own 10 am, through the clocks changing" do
    tokyo = businesses(:two)
    tokyo.update!(timezone: "Asia/Tokyo")
    Tenancy.with_business(tokyo) do
      client = Client.create!(display_name: "Aiko", contact_methods_attributes: [ { kind: "email", value: "aiko@example.com" } ])
      Job.create!(client:, title: "Moss garden").visits.new(scheduled_on: Date.new(2026, 11, 2), timing: "anytime").schedule!(by: nil, notify_client: false)
    end
    book(Date.new(2026, 11, 2)) # New York falls back on Nov 1: 10 am EST is 15:00 UTC, not 14:00
    tokyo_reminders = -> { Tenancy.with_business(tokyo) { EmailMessage.where(kind: "visit_reminder").count } }

    travel_to(Time.utc(2026, 11, 1, 1, 5)) { run_hourly } # 10:05 am in Tokyo, 9:05 pm the night before in New York
    assert_equal [ 1, 0 ], [ tokyo_reminders.call, reminders.size ]
    travel_to(Time.utc(2026, 11, 1, 14, 30)) { run_hourly }
    assert_empty reminders, "9:30 am in New York"
    travel_to(Time.utc(2026, 11, 1, 15, 5)) { run_hourly }
    assert_equal [ 1, 1 ], [ tokyo_reminders.call, reminders.size ]

    book(Date.new(2027, 3, 15)) # springs forward on Mar 14: 10 am EDT is 14:00 UTC
    travel_to(Time.utc(2027, 3, 14, 13, 30)) { run_hourly }
    assert_equal 1, reminders.size
    travel_to(Time.utc(2027, 3, 14, 14, 5)) { run_hourly }
    assert_equal 2, reminders.size
  end

  test "not when reminders are off, the client has no email, or they were emailed about it this morning" do
    visit = book(Date.new(2026, 12, 10))
    @business.update!(client_visit_emails: { "reminder" => "0" })
    travel_to(at("2026-12-09 10:07")) { run_hourly }
    assert_empty reminders
    assert_nil visit.reload.reminder_sent_at

    @business.update!(client_visit_emails: { "reminder" => "1" })
    visit.update_columns(client_told: visit.client_told.merge("emailed_at" => at("2026-12-09 09:00").iso8601))
    travel_to(at("2026-12-09 10:07")) { run_hourly }
    assert_empty reminders, "booked this morning: the booking email was enough"
    assert visit.reload.reminder_sent_at

    Tenancy.with_business(@business) { @client.contact_methods.destroy_all }
    later = book(Date.new(2026, 12, 11))
    travel_to(at("2026-12-10 10:07")) { run_hourly }
    assert_empty reminders
    assert_nil later.reload.reminder_sent_at, "not claimed without an address"
    Tenancy.with_business(@business) { @client.contact_methods.create!(kind: "email", value: "maria@example.com") }
    travel_to(at("2026-12-10 13:07")) { run_hourly }
    assert_equal 1, reminders.size, "an address added that day still gets it"
  end

  test "booked for tomorrow this afternoon: the booking email, not a reminder minutes later too" do
    travel_to(at("2026-12-09 14:05")) do
      Tenancy.with_business(@business) do
        @job.visits.new(scheduled_on: Date.new(2026, 12, 10), timing: "anytime").schedule!(by: @owner)
      end
    end
    travel_to(at("2026-12-09 14:07")) { run_hourly }
    assert_empty reminders, "its booking email is still on its way"
    travel_to(at("2026-12-09 14:09")) { perform_enqueued_jobs(only: VisitClientNoticeJob) }
    travel_to(at("2026-12-09 15:07")) { run_hourly }
    assert_empty reminders
    assert_equal [ "visit_scheduled" ], Tenancy.with_business(@business) { EmailMessage.pluck(:kind) }
  end

  test "a new time on the same day keeps the reminder already sent" do
    visit = book(Date.new(2026, 12, 10))
    travel_to(at("2026-12-09 10:07")) { run_hourly }
    travel_to(at("2026-12-09 15:00")) do
      Tenancy.with_business(@business) { visit.reload.reschedule!({ start_time: "13:00", window_end_time: "15:00" }, by: @owner, notify_client: false) }
    end
    travel_to(at("2026-12-09 16:07")) { run_hourly }
    assert_equal 1, reminders.size
  end
end
