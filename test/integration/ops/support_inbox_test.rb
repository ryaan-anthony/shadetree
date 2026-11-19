require "test_helper"

# OPS-05: the operator inbox: filters, the business beside each ticket, assigning, replying
# (the member hears in the app and by email), internal notes, status, and the audit log.
class Ops::SupportInboxTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @ticket = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Tax on one invoice", category: "billing", body: "How?", page: "/admin/invoices/x", browser: "TestBrowser") }
    @other = as_business(businesses(:two)) { SupportTicket.open!(opened_by: users(:two), subject: "Feature idea", category: "feature", body: "Dark mode") }
  end

  test "non-operators get not found" do
    sign_in users(:one)
    get admin_root_path
    get ops_tickets_path
    assert_response :not_found
  end

  test "the inbox filters by status, category, plan and assignee" do
    sign_in_operator(users(:two))
    get ops_tickets_path
    assert_select "#tickets > li", 2
    assert_select "#nav-support", /2/
    get ops_tickets_path(category: "billing")
    assert_select "#tickets > li", 1
    assert_select "#ticket-#{@ticket.uid}", /Test Business One/
    as_business(businesses(:two)) { @other.change_status!("resolved") }
    get ops_tickets_path
    assert_select "#ticket-#{@other.uid}", 0
    get ops_tickets_path(status: "resolved")
    assert_select "#ticket-#{@other.uid}"
    get ops_tickets_path(status: "any", plan: plans(:starter).id)
    assert_select "#tickets", 0
    as_business(@business) { @ticket.update!(assignee: users(:two)) }
    get ops_tickets_path(assignee: "me")
    assert_select "#tickets > li", 1
    get ops_tickets_path(assignee: "none", status: "any")
    assert_select "#ticket-#{@other.uid}"
    assert_select "#ticket-#{@ticket.uid}", 0
  end

  test "an operator assigns, replies, notes and sets status; the member hears; each is audited" do
    sign_in_operator(users(:two))
    get ops_ticket_path(@ticket)
    assert_response :success
    assert_select "#ticket-business", /Test Business One/
    assert_select "a[href=?]", ops_business_path(@business)
    assert_select "body", /TestBrowser/

    patch assign_ops_ticket_path(@ticket), params: { assignee: users(:two).id }
    assert_equal users(:two), @ticket.reload.assignee
    patch assign_ops_ticket_path(@ticket), params: { assignee: users(:one).id }
    assert_nil @ticket.reload.assignee, "only operators can be assigned"

    assert_enqueued_emails 1 do
      post reply_ops_ticket_path(@ticket), params: { body: "Open the invoice, then Tax → None.", status: "waiting" }
    end
    assert_equal [ "waiting", true ], [ @ticket.reload.status, @ticket.waiting_since.present? ]
    notification = as_business(@business) { Notification.find_by!(user: users(:one), kind: "support_reply") }
    assert_equal "/admin/help/#{@ticket.uid}", notification.path
    mail = SupportMailer.with(business_id: @business.id, message_id: as_business(@business) { @ticket.messages.last.id }, user: users(:one)).reply
    assert_equal [ "support@getshadetree.com" ], mail.reply_to
    assert_match "[##{@ticket.uid}]", mail.subject
    assert_match "ticket-#{@ticket.uid}-", mail.message_id
    assert_match "Tax → None", mail.text_part.body.to_s

    post note_ops_ticket_path(@ticket), params: { body: "Customer is tax exempt per building" }
    assert as_business(@business) { @ticket.messages.last.internal? }
    post reply_ops_ticket_path(@ticket), params: { body: "" }
    assert_match "Write a reply", flash[:alert]
    patch status_ops_ticket_path(@ticket), params: { status: "resolved" }
    assert_equal "resolved", @ticket.reload.status

    assert_equal({ "ticket.assigned" => 2, "ticket.replied" => 1, "ticket.noted" => 1, "ticket.status_changed" => 1 },
                 AuditEntry.where(business: @business).group(:action).count)
    assert AuditEntry.where(action: "ticket.replied").all? { _1.data["ticket"] == @ticket.uid }
  end
end
