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
    assert_match "Only an operator", flash[:alert]
    assert_equal users(:two), @ticket.reload.assignee, "a non-operator doesn't unassign"

    assert_enqueued_emails 1 do
      post reply_ops_ticket_path(@ticket), params: { body: "Open the invoice, then Tax → None.", status: "waiting" }
    end
    assert_match "Reply sent to John Doe", flash[:notice]
    assert_equal [ "waiting", true ], [ @ticket.reload.status, @ticket.waiting_since.present? ]
    notification = as_business(@business) { Notification.find_by!(user: users(:one), kind: "support_reply") }
    assert_equal "/admin/help/#{@ticket.uid}", notification.path
    mail = SupportMailer.with(business_id: @business.id, message_id: as_business(@business) { @ticket.messages.last.id }, user: users(:one)).reply
    assert_equal [ "support@getshadetree.com" ], mail.reply_to
    assert_match "[##{@ticket.uid}]", mail.subject
    assert_match "ticket-#{@ticket.uid}-", mail.message_id
    assert_match "Tax → None", mail.text_part.body.to_s
    assert_match "Reply in Shadetree.", mail.text_part.body.to_s
    assert_no_match "Reply to this email", mail.html_part.body.to_s

    post note_ops_ticket_path(@ticket), params: { body: "Customer is tax exempt per building" }
    assert as_business(@business) { @ticket.messages.last.internal? }
    post reply_ops_ticket_path(@ticket), params: { body: "" }
    assert_match "Write a reply", flash[:alert]
    patch status_ops_ticket_path(@ticket), params: { status: "resolved" }
    assert_equal "resolved", @ticket.reload.status

    assert_equal({ "ticket.viewed" => 1, "ticket.assigned" => 1, "ticket.replied" => 1, "ticket.noted" => 1, "ticket.status_changed" => 1 },
                 AuditEntry.where(business: @business).group(:action).count)
    assert AuditEntry.where(action: "ticket.replied").all? { _1.data["ticket"] == @ticket.uid }
  end

  test "replies reach everyone in the business who wrote on the ticket, or its Owners when they've gone" do
    @ticket.update_columns(category: "question") # billing tickets are Owner-only (see support_ticket_test)
    @business.add_user(users(:two), role: "admin")
    as_business(@business) { @ticket.reply_from_member!(users(:two), "Same problem here") }
    assert_equal [ users(:one), users(:two) ].to_set, SupportNotifier.recipients(@ticket).to_set
    business_users(:one).update_columns(role: "admin") # so the business has another Owner to fall back to
    @business.business_users.find_by(user: users(:two)).update_columns(role: "owner")
    @business.business_users.where(user: [ users(:one), users(:two) ]).each { _1.update_columns(active: false) }
    assert_empty SupportNotifier.recipients(@ticket), "no active members at all"
    @business.business_users.find_by(user: users(:two)).update_columns(active: true)
    as_business(@business) { @ticket.messages.where(author: users(:two)).delete_all }
    assert_equal [ users(:two) ], SupportNotifier.recipients(@ticket), "nobody who wrote is left: the Owners"
  end

  test "operators open screenshots through a checked, short-lived link; members can't use it" do
    as_business(@business) { @ticket.messages.first.files.attach(io: file_fixture("logo.png").open, filename: "shot.png", content_type: "image/png") }
    file = as_business(@business) { @ticket.messages.first.files.first }
    sign_in_operator(users(:two))
    get ops_ticket_path(@ticket)
    assert_select "a[href=?]", ops_ticket_file_path(@ticket, file)
    get ops_ticket_file_path(@ticket, file)
    assert_match "/rails/active_storage/disk/", response.location
    get ops_ticket_file_path(@other, file)
    assert_response :not_found, "a file is found only under its own ticket"
  end
end
