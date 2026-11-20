require "test_helper"

# OPS-05: stale "Waiting on you" tickets are resolved with a notice to the member.
class SupportTicketTest < ActiveSupport::TestCase
  include PermissionHelpers
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

  test "a reply or status change while the job runs wins; one failure doesn't stop the rest" do
    business = businesses(:one)
    first, second = as_business(business) do
      %w[First Second].map { SupportTicket.open!(opened_by: users(:one), subject: _1, category: "question", body: "?") }
    end
    as_business(business) do
      [ first, second ].each { |ticket| travel_to(10.days.ago) { ticket.reply_from_operator!(users(:two), "Does this help?") } }
      seen_waiting = SupportTicket.find(first.id) # as the job found it
      first.reply_from_member!(users(:one), "Not yet!") # then the member answers
      assert_not seen_waiting.resolve_if_still_unanswered!(SupportTicket::AUTO_RESOLVE_AFTER.ago)
      assert_equal "open", first.reload.status
      assert_not first.messages.exists?(source: "system")
    end

    as_business(business) { first.reply_from_operator!(users(:two), "Try now?") && first.update_columns(waiting_since: 10.days.ago) }
    calls = 0
    original = SupportNotifier.method(:replied)
    SupportNotifier.define_singleton_method(:replied) do |*args, **opts|
      calls += 1
      raise "mail server down" if calls == 1

      original.call(*args, **opts)
    end
    assert_equal 1, SupportTicket.resolve_stale!
    assert_equal 2, calls, "the second ticket was still handled"
  ensure
    SupportNotifier.define_singleton_method(:replied, original) if original
  end

  test "reply notices only go to people who may still see the ticket" do
    business = businesses(:one)
    helper = member_with_role("admin", business:)
    billing = as_business(business) { SupportTicket.open!(opened_by: users(:one), subject: "Card", category: "billing", body: "Declined") }
    as_business(business) { billing.reply_from_member!(helper, "I'll add the new card") } # before visibility rules, or before a demotion
    assert_equal [ users(:one) ], SupportNotifier.recipients(billing), "the admin wrote on it but can't see billing tickets"

    question = as_business(business) { SupportTicket.open!(opened_by: users(:one), subject: "Export", category: "question", body: "?") }
    as_business(business) { question.reply_from_member!(helper, "Me too") }
    assert_includes SupportNotifier.recipients(question), helper
    business.business_users.find_by!(user: helper).update!(role: "technician")
    assert_not_includes SupportNotifier.recipients(question), helper, "demoted: it isn't their ticket any more"
  end

  test "a bad SUPPORT_AUTO_RESOLVE_DAYS falls back to 7" do
    assert_equal [ 7, 7, 7, 14 ], [ "seven", "-3", "", "14" ].map { SupportTicket.auto_resolve_days(_1) }
  end
end
