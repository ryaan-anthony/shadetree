require "test_helper"

# MKT-02 part 2: contact-form messages in the operator console. Operators only (everyone else
# gets "not found"), spam on its own tab, handled or open, and deletes need a fresh code and
# are in the audit log without the sender's details.
class Ops::ContactMessagesTest < ActionDispatch::IntegrationTest
  setup do
    @founder = users(:one)
    @operator = Operator.grant!(@founder)
    @older = ContactMessage.create!(name: "Dana Whitfield", email: "dana@example.com", business_name: "Whitfield Cleaning",
                                    body: "Can each cleaner see\nonly their own visits?", created_at: 2.days.ago)
    @newer = ContactMessage.create!(name: "Sam <b>Lee</b>", email: "sam@example.com", body: "Do you send <script>reminders</script>?", created_at: 1.hour.ago)
    @spam = ContactMessage.create!(name: "SEO Pro", email: "seo@example.com", body: "Cheap backlinks", spam_reason: "spam words")
  end

  def code_for(operator) = Totp.code(operator.reload.otp_secret, Time.current.to_i / Totp::STEP)

  def enter_console
    sign_in @founder
    get ops_root_path
    follow_redirect! # setup
    post ops_two_factor_setup_path, params: { code: code_for(@operator), password: "password123" }
  end

  test "non-operators, signed in or not, get not found and change nothing" do
    get ops_contact_messages_path
    assert_response :not_found
    sign_in users(:two)
    get ops_contact_messages_path
    assert_response :not_found
    get ops_contact_message_path(@older)
    assert_response :not_found
    delete ops_contact_message_path(@older)
    assert_response :not_found
    delete erase_ops_contact_message_path(@older)
    assert_response :not_found
    patch ops_contact_message_path(@older), params: { handled: "1" }
    assert_response :not_found
    assert_equal 3, ContactMessage.count
    assert_nil @older.reload.handled_at
  end

  test "an operator must verify with two-factor first" do
    @operator.update!(otp_secret: Totp.random_secret, otp_enabled_at: Time.current)
    sign_in @founder
    get ops_contact_messages_path
    assert_redirected_to new_ops_two_factor_verification_path
  end

  test "messages are listed newest first, with spam on its own tab, and open to read" do
    enter_console
    get ops_root_path
    assert_select "#open-contact-messages", /2 open messages/
    get ops_contact_messages_path
    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "#contact-messages li", 2
    assert_equal [ "contact-message-#{@newer.uid}", "contact-message-#{@older.uid}" ], css_select("#contact-messages li").map { _1["id"] }
    assert_select "#contact-message-#{@spam.uid}", 0
    assert_select "nav .tab[aria-current=page]", /Open\s+2/

    get ops_contact_messages_path(tab: "spam")
    assert_select "#contact-messages li", 1
    assert_select "#contact-message-#{@spam.uid}", /Spam words/

    get ops_contact_message_path(@newer)
    assert_response :success
    assert_select "#message-body", text: /Do you send <script>reminders<\/script>\?/, count: 1
    assert_select "#message-body script", 0, "what people type is shown as text"
    assert_select "h1", "Message from Sam <b>Lee</b>"
    assert_select "a[href^=?]", "mailto:sam@example.com?subject=", text: /Reply by email/
    get ops_contact_message_path(id: "nope")
    assert_response :not_found
  end

  test "an operator marks a message handled, and open again" do
    enter_console
    patch ops_contact_message_path(@older), params: { handled: "1" }
    assert_redirected_to ops_contact_message_path(@older)
    assert @older.reload.handled_at
    get ops_contact_messages_path(tab: "handled")
    assert_select "#contact-message-#{@older.uid}"
    get ops_contact_messages_path
    assert_select "#contact-message-#{@older.uid}", 0
    patch ops_contact_message_path(@older), params: { handled: "0" }
    assert_nil @older.reload.handled_at
  end

  test "deleting a message needs a fresh code and is audited without the sender's details" do
    enter_console
    travel 6.minutes do
      delete ops_contact_message_path(@spam)
      assert_redirected_to new_ops_two_factor_verification_path(recent: 1)
      assert ContactMessage.exists?(@spam.id)
      post ops_two_factor_verification_path, params: { code: code_for(@operator) }
      delete ops_contact_message_path(@spam)
      assert_redirected_to ops_contact_messages_path(tab: "spam")
    end
    assert_not ContactMessage.exists?(@spam.id)
    entry = AuditEntry.find_by!(action: "contact_message.deleted")
    assert_equal [ @founder, { "message" => @spam.uid, "spam" => true } ], [ entry.operator_user, entry.data ]
    assert_no_match "seo@example.com", entry.attributes.to_json
    get ops_audit_entries_path(action_name: "contact_message.deleted")
    assert_select "#audit-entries li", /Deleted a contact message.*Message #{@spam.uid} \(spam\)/m
  end

  test "everything from one address can be deleted on request, and that's audited" do
    again = ContactMessage.create!(name: "Dana", email: "dana@example.com", body: "Following up")
    enter_console
    get ops_contact_message_path(again)
    assert_select "#erase-sender"
    assert_match "2 messages", response.body
    assert_match "delete those emails there too", response.body, "the support inbox copies are mentioned"
    delete erase_ops_contact_message_path(again)
    assert_redirected_to ops_contact_messages_path
    assert_equal [ @newer, @spam ].sort, ContactMessage.all.sort
    entry = AuditEntry.find_by!(action: "contact_message.erased")
    assert_equal({ "count" => 2 }, entry.data)
    assert_no_match "dana@example.com", entry.attributes.to_json
    get ops_audit_entries_path(action_name: "contact_message.erased")
    assert_select "#audit-entries li", /2 messages/
  end
end
