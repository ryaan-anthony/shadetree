require "test_helper"

# OPS-05: members ask Shadetree for help and follow the replies; tickets stay in their business.
class Admin::SupportTicketsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    users(:one).update_columns(last_business_id: @business.id) # user one is also in business two
  end

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

  test "technicians see only their own tickets, and billing tickets need the billing permission" do
    tech = member_with_role("technician")
    admin = member_with_role("admin")
    billing, question = as_business(@business) do
      [ SupportTicket.open!(opened_by: users(:one), subject: "Card declined", category: "billing", body: "Help",
                            files: [ fixture_file_upload("logo.png", "image/png") ]),
        SupportTicket.open!(opened_by: users(:one), subject: "How do I export?", category: "question", body: "Hi") ]
    end
    own = as_business(@business) { SupportTicket.open!(opened_by: tech, subject: "My plan?", category: "billing", body: "Hi") }
    file = as_business(@business) { billing.messages.first.files.first }

    sign_in tech
    get admin_support_tickets_path
    assert_select "#ticket-#{own.uid}", 1, "their own, billing or not"
    assert_select "#ticket-#{question.uid}", 0
    assert_select "#ticket-#{billing.uid}", 0
    [ admin_support_ticket_path(question), admin_support_ticket_path(billing), admin_support_ticket_file_path(billing, file) ].each do |path|
      get path
      assert_response :not_found
    end
    post reply_admin_support_ticket_path(question), params: { support_message: { body: "x" } }
    assert_response :not_found
    sign_out :user

    sign_in admin
    get admin_support_tickets_path
    assert_select "#ticket-#{question.uid}", 1
    assert_select "#ticket-#{billing.uid}", 0, "billing is owner-only"
    assert_select "#ticket-#{own.uid}", 0, "another member's billing ticket"
    get admin_support_ticket_path(billing)
    assert_response :not_found
    sign_out :user

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_support_tickets_path
    [ billing, question, own ].each { assert_select "#ticket-#{_1.uid}", 1 }
  end

  test "screenshots are served only to members of the business, through a short-lived link" do
    ticket = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Logo", category: "bug", body: "See", files: [ fixture_file_upload("logo.png", "image/png") ]) }
    file = as_business(@business) { ticket.messages.first.files.first }
    path = admin_support_ticket_file_path(ticket, file)
    get path
    assert_redirected_to new_user_session_path, "signed out"

    sign_in users(:two)
    get admin_support_tickets_path
    assert_not_found_across_businesses { get admin_support_ticket_file_path(ticket, file) }
    sign_out :user

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid } # the session still names business two
    get admin_support_ticket_path(ticket)
    assert_select "a[href=?]", path
    assert_no_match "/rails/active_storage/blobs/", response.body
    get path
    assert_response :redirect
    assert_match "/rails/active_storage/disk/", response.location
    note = as_business(@business) { ticket.note!(users(:two), "Internal").tap { _1.files.attach(io: file_fixture("logo.png").open, filename: "x.png") } }
    get admin_support_ticket_file_path(ticket, as_business(@business) { note.files.first })
    assert_response :not_found, "files on internal notes aren't for members"
  end

  test "unconfirmed members can ask, but not attach screenshots" do
    sign_in users(:unconfirmed)
    as_business(@business) { @business.add_user(users(:unconfirmed)) }
    get admin_support_tickets_path
    ask(files: [ fixture_file_upload("logo.png", "image/png") ])
    assert_match "Confirm your email address to attach screenshots", flash[:alert]
    assert_no_difference(-> { as_business(@business) { SupportTicket.count } }) { ask(files: [ fixture_file_upload("logo.png", "image/png") ]) }
    assert_difference(-> { as_business(@business) { SupportTicket.count } }) { ask }
  end

  test "asking is rate limited per person and per business" do
    sign_in users(:one)
    get admin_support_tickets_path
    store = ActionController::Base.cache_store
    over = ->(scope) { store.define_singleton_method(:increment) { |key, *, **| key.include?(scope) ? 10_000 : 1 } }
    over.call(":#{users(:one).id}")
    assert_no_difference(-> { as_business(@business) { SupportTicket.count } }) { ask }
    assert_redirected_to admin_support_tickets_path
    assert_match "a lot of messages", flash[:alert]
    over.call("business:#{@business.id}")
    assert_no_difference(-> { as_business(@business) { SupportTicket.count } }) { ask }
    assert_match "a lot of messages", flash[:alert]
  ensure
    store.singleton_class.remove_method(:increment) if store.singleton_class.method_defined?(:increment, false)
  end

  test "the list is paginated, and the thread doesn't query per message" do
    as_business(@business) { 27.times { |n| SupportTicket.open!(opened_by: users(:one), subject: "Q#{n}", category: "question", body: "?") } }
    sign_in users(:one)
    get admin_support_tickets_path
    assert_select "#support-tickets > li", Admin::SupportTicketsController::PER_PAGE
    get admin_support_tickets_path(page: 2)
    assert_select "#support-tickets > li", 2
    ticket = as_business(@business) { SupportTicket.last.tap { |t| 5.times { t.reply_from_member!(users(:one), "more") } } }
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get admin_support_ticket_path(ticket) }
    few = queries
    as_business(@business) { 10.times { ticket.reply_from_member!(users(:one), "even more") } }
    queries = 0
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get admin_support_ticket_path(ticket) }
    assert_equal few, queries, "queries don't grow with the thread"
  end

  test "setting Waiting on you again doesn't restart its clock" do
    ticket = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Q", category: "question", body: "?") }
    as_business(@business) do
      travel_to(3.days.ago) { ticket.reply_from_operator!(users(:two), "Try this?") }
      started = ticket.reload.waiting_since
      ticket.reply_from_operator!(users(:two), "Any luck?")
      assert_equal started, ticket.reload.waiting_since
      ticket.change_status!("open")
      assert_nil ticket.reload.waiting_since
    end
  end
end
