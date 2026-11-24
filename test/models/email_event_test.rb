require "test_helper"

# NTF-05: a stored late bounce or complaint goes through send time's rules, once, in the email's
# business: who's blocked, what the email says, the timeline, and whether the team is told.
class EmailEventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include EmailEventHelpers

  setup do
    @business = businesses(:one)
    @email = sent_email(@business, cc: "office@example.com, ana@example.com")
  end

  def report(email = @email, type: "bounce", status: "5.1.1", reply_code: "550", recipient: email.to, key: SecureRandom.hex(4), at: Time.current)
    event = EmailEventIngress::Event.new(key:, type:, message_id: email.provider_message_id, reference: nil, recipient:, status:, reply_code:, occurred_at: at)
    perform_enqueued_jobs(only: ProcessEmailEventJob) { EmailEvent.receive(event) }
  end

  def fresh(email = @email) = as_business(@business) { email.reload }
  def notifications = as_business(@business) { Notification.where(kind: "email_not_delivered").count }
  def timeline(kind) = as_business(@business) { ClientEvent.where(kind:).count }
  def blocked = as_business(@business) { EmailSuppression.order(:email).pluck(:email, :reason) }

  test "a mailbox status marks the email Address refused, blocks the address and tells the team, as at send time" do
    at = 2.minutes.ago
    report(at:)
    email = fresh
    assert_equal [ "bounced", "Address refused", "550 5.1.1", false ], [ email.status, email.status_label, email.reply_code, email.our_side? ]
    assert_equal "The mail server refused this address (550 5.1.1).", email.error
    assert_in_delta at, email.bounced_at, 1
    assert_equal [ [ "maria@example.com", "hard_bounce" ] ], blocked
    assert_equal [ 1, 1 ], [ notifications, timeline("email_bounced") ]
    assert_equal email, as_business(@business) { email.related.reload.undelivered_email }

    report(key: "another-report")
    assert_equal [ 1, 1 ], [ notifications, timeline("email_bounced") ], "once only: a second report changes nothing"
  end

  test "any other permanent status is Couldn't send, without blaming the address, and never our side" do
    report(status: "5.7.1", reply_code: nil)
    email = fresh
    assert_equal [ "failed", "Couldn't send", "5.7.1", false ], [ email.status, email.status_label, email.reply_code, email.our_side? ]
    assert_equal "The mail server refused the email (5.7.1).", email.error
    assert_equal "The receiving mail server rejected the email.", email.problem_reason
    assert_empty blocked
    assert_equal 1, notifications
  end

  test "an email that already failed or bounced keeps what happened first" do
    as_business(@business) { @email.mark!("failed", error: "The mail server refused the email (554 5.7.1).", announce: true) }
    report
    assert_equal [ "failed", "The mail server refused the email (554 5.7.1)." ], [ fresh.status, fresh.error ]
    assert_empty blocked
  end

  test "once the client approved, declined or asked for changes: only the timeline, no notification or warning" do
    %w[approved declined changes_requested].each do |status|
      email = sent_email(@business)
      as_business(@business) { email.related.update_column(:status, status) }
      assert_no_difference(-> { notifications }) do
        assert_difference(-> { timeline("email_bounced") }) { report(email) }
      end
      assert_equal "bounced", fresh(email).status
      assert_nil as_business(@business) { email.related.reload.undelivered_email }
    end
  end

  test "a paid or void invoice, a receipt or a visit email: only the timeline" do
    client = as_business(@business) { Client.create!(display_name: "Ana Ruiz", contact_methods_attributes: [ { kind: "email", value: "ana@example.com" } ]) }
    paid = as_business(@business) { Invoice.start(client:).tap { _1.update_column(:status, "paid") } }
    void = as_business(@business) { Invoice.start(client:).tap { _1.update_column(:status, "void") } }
    sent = as_business(@business) { Invoice.start(client:).tap { _1.update_column(:status, "sent") } }
    emails = as_business(@business) do
      [ [ "invoice_sent", paid ], [ "invoice_sent", void ], [ "visit_scheduled", nil ], [ "invoice_sent", sent ] ].map do |kind, related|
        EmailMessage.create!(kind:, to: "ana@example.com", related: related || Job.create!(client:, title: "Gutters"))
                    .tap { _1.mark!("sent", at: 1.hour.ago, provider_message_id: "#{SecureRandom.uuid}@getshadetree.com") }
      end
    end
    emails.first(3).each { report(_1) }
    assert_equal [ 0, 3 ], [ notifications, timeline("email_bounced") ], "void is treated as paid (owner, 2026-11-24)"
    report(emails.last)
    assert_equal 1, notifications, "an invoice still waiting to be paid is warned about"
  end

  test "a CC bounce blocks only that CC and is recorded; the email stays delivered, with no warning" do
    report(recipient: "ana@example.com", status: "5.1.1")
    report(recipient: "office@example.com", status: "5.7.1", reply_code: "554")
    email = fresh
    assert_equal "sent", email.status
    assert_equal [ [ 1, "mailbox", "550 5.1.1" ], [ 0, "refused", "554 5.7.1" ] ], email.cc_problems.map { _1.values_at("position", "reason", "code") }
    assert_equal [ [ "ana@example.com", "hard_bounce" ] ], blocked
    assert_equal [ 0, 0 ], [ notifications, timeline("email_bounced") ]

    report(recipient: "ana@example.com", key: "again")
    assert_equal 2, fresh.cc_problems.size, "each CC once"
  end

  test "a complaint blocks the address, marks the email Marked as spam, goes on the timeline, and tells no one" do
    report(type: "complaint", status: nil, reply_code: nil, recipient: nil)
    email = fresh
    assert_equal [ "complained", "Marked as spam", false ], [ email.status, email.status_label, email.problem? ]
    assert email.complained_at
    assert_equal [ [ "maria@example.com", "complaint" ] ], blocked
    assert_equal [ 0, 1, 0 ], [ notifications, timeline("email_complained"), timeline("email_bounced") ]
    assert_nil as_business(@business) { email.related.reload.undelivered_email }, "no Resend prompt"
  end

  test "a superseded send's bounce changes the email but isn't announced" do
    quote = @email.related
    sent_email(@business, quote:)
    report
    assert_equal [ "bounced", 0, 0 ], [ fresh.status, notifications, timeline("email_bounced") ]
  end

  test "events are processed in their own business, and pruned after 90 days with old counts" do
    other = sent_email(businesses(:two))
    report(other)
    assert_equal "bounced", as_business(businesses(:two)) { other.reload.status }
    assert_equal "sent", fresh.status
    assert_raises(ActiveRecord::RecordNotFound) { as_business(@business) { EmailEvent.find(Tenancy.across_businesses(reason: "test") { EmailEvent.last.id }) } }

    EmailEventTally.count!(:received, day: 91.days.ago.to_date)
    travel_to(91.days.from_now) { PruneEmailEventsJob.perform_now }
    assert_equal 0, Tenancy.across_businesses(reason: "test") { EmailEvent.count }
    assert_equal 0, EmailEventTally.where(day: ...80.days.ago.to_date).count
  end
end
