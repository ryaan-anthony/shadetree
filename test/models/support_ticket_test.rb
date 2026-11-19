require "test_helper"

# OPS-05: stale "Waiting on you" tickets are resolved with a notice to the member.
class SupportTicketTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "tickets waiting too long are resolved, with a notice in the thread, the app and email" do
    business = businesses(:one)
    stale, fresh = as_business(business) do
      [ "Old", "New" ].map { SupportTicket.open!(opened_by: users(:one), subject: _1, category: "question", body: "?") }
    end
    as_business(business) do
      travel_to(SupportTicket::AUTO_RESOLVE_AFTER.ago - 1.hour) { stale.reply_from_operator!(users(:two), "Does this help?") }
      fresh.reply_from_operator!(users(:two), "Does this help?")
    end

    assert_enqueued_emails(1) { assert_equal 1, ResolveStaleSupportTicketsJob.perform_now }
    assert_equal [ "resolved", "waiting" ], [ stale.reload.status, fresh.reload.status ]
    as_business(business) do
      assert_equal [ SupportTicket::AUTO_RESOLVE_NOTICE, "system" ], stale.messages.last.slice(:body, :source).values
      assert Notification.exists?(user: users(:one), kind: "support_reply", title: "Resolved: Old")
    end
    entry = AuditEntry.find_by!(action: "ticket.auto_resolved")
    assert_equal [ "system", business ], [ entry.operator_email, entry.business ]
  end
end
