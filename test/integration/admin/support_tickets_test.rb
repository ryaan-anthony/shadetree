require "test_helper"

# OPS-05: members ask Shadetree for help and follow the replies; tickets stay in their business.
class Admin::SupportTicketsTest < ActionDispatch::IntegrationTest
  setup { @business = businesses(:one) }

  def ask(**overrides)
    post admin_support_tickets_path, params: { support_ticket: { subject: "Tax on one invoice", category: "billing", body: "How do I remove tax from INV-1?",
                                                                 page: "/admin/invoices/abc" }.merge(overrides) },
                                     headers: { "User-Agent" => "Mozilla/5.0 TestBrowser" }
  end

  test "any member opens a ticket from the Help menu, with the page and browser attached" do
    sign_in users(:one)
    get admin_root_path
    assert_select "#help-menu"
    assert_select "a[href=?]", new_admin_support_ticket_path(from: "/admin")
    get new_admin_support_ticket_path(from: "https://evil.example/admin")
    assert_select "input[name='support_ticket[page]']:not([value])"

    ask(subject: "", body: "")
    assert_response :unprocessable_content
    assert_select ".banner", /Subject can't be blank/

    png = fixture_file_upload("logo.png", "image/png")
    ask(files: [ png ])
    ticket = as_business(@business) { SupportTicket.last }
    assert_redirected_to admin_support_ticket_path(ticket)
    assert_equal [ "open", "billing", "/admin/invoices/abc", "Mozilla/5.0 TestBrowser", users(:one) ], [ ticket.status, ticket.category, ticket.page, ticket.browser, ticket.opened_by ]
    as_business(@business) { assert ticket.messages.first.files.attached? }

    follow_redirect!
    assert_select "#messages > li", 1
    assert_select "#messages", /How do I remove tax/
  end

  test "members see their business's tickets and replies, never internal notes; a reply reopens" do
    ticket = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Logo", category: "bug", body: "Blurry logo") }
    as_business(@business) do
      ticket.reply_from_operator!(users(:two), "Try a bigger PNG.")
      ticket.note!(users(:two), "Internal: known resize bug")
      ticket.change_status!("resolved")
    end
    sign_in users(:one)
    get admin_support_tickets_path
    assert_select "#ticket-#{ticket.uid}", /Logo.*Resolved/m
    get admin_support_ticket_path(ticket)
    assert_select "#messages > li", 2
    assert_select "#messages", /Shadetree support/
    assert_no_match "known resize bug", response.body
    assert_no_match "user2@example.com", response.body

    post reply_admin_support_ticket_path(ticket), params: { support_message: { body: "Still blurry" } }
    assert_equal "open", ticket.reload.status
    assert_nil ticket.resolved_at
    post reply_admin_support_ticket_path(ticket), params: { support_message: { body: "" } }
    assert_response :unprocessable_content
  end

  test "technicians can ask too; other businesses' tickets are not found" do
    theirs = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Theirs", category: "question", body: "Hi") }
    sign_in users(:two)
    get admin_support_tickets_path
    assert_select "#ticket-#{theirs.uid}", 0
    assert_not_found_across_businesses { get admin_support_ticket_path(theirs) }
    assert_not_found_across_businesses { post reply_admin_support_ticket_path(theirs), params: { support_message: { body: "x" } } }
    sign_out :user

    sign_in users(:one)
    post switch_admin_business_path, params: { business: businesses(:two).uid } # a technician there
    ask
    ticket = as_business(businesses(:two)) { SupportTicket.last }
    assert_redirected_to admin_support_ticket_path(ticket)
    get admin_support_tickets_path
    assert_select "#ticket-#{ticket.uid}"
    assert_select "#ticket-#{theirs.uid}", 0
  end
end
