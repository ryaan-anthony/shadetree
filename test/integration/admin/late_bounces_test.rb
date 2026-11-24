require "test_helper"

# NTF-05: a report posted to /inbound/email_events shows up where a send-time refusal does: the
# quote's warning with Resend, the list badge, the timeline and the send history; a CC's and a
# complaint's only where the spec says. The operator console counts the reports.
class Admin::LateBouncesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include EmailEventHelpers

  setup do
    @business = businesses(:one)
    @email = sent_email(@business, cc: "office@example.com", by: users(:one))
    @quote = @email.related
  end

  def report(body) = perform_enqueued_jobs(only: ProcessEmailEventJob) { post(inbound_email_events_path, params: body, headers: event_headers(body)) }

  def sign_in_owner
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "a late mailbox bounce: the warning with its code and Resend, the badge, the timeline and the history" do
    with_email_events { report(event_json(@email)) }
    sign_in_owner
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem h2", "Email not delivered"
    assert_select "#quote-delivery-problem", /The receiving mail server says this address doesn't exist or can't take email\./
    assert_select "#quote-delivery-problem .font-mono", "550 5.1.1"
    assert_select "#quote-delivery-problem a[href=?]", new_admin_quote_send_path(@quote), text: "Resend"
    assert_select ".card", /Address refused \(The mail server refused this address \(550 5.1.1\)\.\)/

    get admin_quotes_path
    assert_select "#quote-#{@quote.uid} .badge-danger", "Email not delivered"
    get admin_client_path(@quote.client)
    assert_select "#client-timeline li", /Email not delivered.*Quote #{@quote.number} to maria@example.com/m
  end

  test "a CC bounce shows in the send history only; a complaint marks the email and goes on the timeline" do
    with_email_events do
      report(event_json(@email, recipient: "office@example.com", status: "5.1.1"))
      sign_in_owner
      get admin_quote_path(@quote)
      assert_select "#quote-delivery-problem", 0
      assert_select ".card", /cc office@example.com: .*Address refused.* \(550 5.1.1\)/m

      report(event_json(@email, type: "complaint", status: nil, reply_code: nil))
    end
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem", 0
    assert_select ".card", /Marked as spam/
    get admin_client_path(@quote.client)
    assert_select "#client-timeline li", /Marked an email as spam \(Quote #{@quote.number}\)/
    assert_select "[id^=undeliverable-]", /was marked as\s+spam, so emails to it are paused/
  end

  test "the operator console counts received, matched and dropped reports over the last 7 days" do
    with_email_events do
      report(event_json(@email))
      report(event_json(@email, message_id: "<unknown@getshadetree.com>"))
    end
    EmailEventTally.count!(:received, day: 8.days.ago.utc.to_date)
    sign_in_operator
    get ops_root_path
    assert_select "#email-events-received", "2"
    assert_select "#email-events-matched", "1"
    assert_select "#email-events-dropped", "1"
  end
end
