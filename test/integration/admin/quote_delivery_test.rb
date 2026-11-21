require "test_helper"

# QA #274 (QTE-04, QTE-05, PAY-02, NTF-02): an email to the client that didn't arrive is warned
# about on the quote, in the lists and on the client's timeline, and the team is told; the quote
# stays Sent (owner decision 2026-11-21).
class Admin::QuoteDeliveryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  REFUSED = "The mail server refused this address (550 5.1.1)."

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @owner = users(:one)
    @maria = as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]) }
    @quote = as_business(@business) do
      quote = Quote.start(client: @maria)
      quote.title = "Cricket in the basement"
      quote.sync_line_items([ { "key" => "a", "name" => "Inspection", "quantity" => "1", "unit_price" => "60", "taxable" => "0" } ])
      quote.save!
      quote
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def fresh = as_business(@business) { @quote.reload }

  # An emailed send of the quote's current revision, and its email marked as given.
  def emailed(status = nil, error: REFUSED)
    as_business(@business) do
      email = EmailMessage.create!(kind: "quote_sent", to: "maria@example.com", related: @quote)
      @quote.reload.mark_sent!(by: @owner, channel: "email", recipient: email.to, email_message: email)
      status ? email.mark!(status, error:) : email
    end
  end

  test "a 554 at send time: a prominent warning with the reason, code and time, Resend, the status stays Sent, and the team is told" do
    with_fake_pdf_renderer do
      post admin_quote_send_path(@quote), params: { quote_send: { to: "maria@example.com", subject: "Your quote", message: "Hi" } }
      FakeSmtpServer.run(rcpt: "554 5.7.1 <maria@example.com>: Recipient address rejected: Access denied") do |settings|
        previous = [ QuoteMailer.delivery_method, QuoteMailer.smtp_settings ]
        QuoteMailer.delivery_method = :smtp
        QuoteMailer.smtp_settings = settings
        perform_enqueued_jobs(only: ClientMailDeliveryJob)
      ensure
        QuoteMailer.delivery_method, QuoteMailer.smtp_settings = previous
      end
    end
    assert_equal "sent", fresh.status

    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem[aria-labelledby=quote-delivery-problem-h] h2", "Email not delivered"
    assert_select "#quote-delivery-problem", /to maria@example.com on .*\d{4}.* didn't arrive\. The receiving mail server rejected the email\./
    assert_select "#quote-delivery-problem", /The quote is still sent and its link still works/
    assert_select "#quote-delivery-problem .font-mono", "554 5.7.1"
    assert_select "#quote-delivery-problem a[href=?]", new_admin_quote_send_path(@quote), text: "Resend"
    assert_select "dd", /Sent/ # the status badge
    assert_select "#quote-revisions", 0 # one revision: no revisions list
    assert_select ".card", /Couldn't send \(The mail server refused the email \(554 5.7.1\)\.\)/ # the send history keeps the code

    get admin_quotes_path
    assert_select "#quote-#{@quote.uid} .badge-danger", "Email not delivered"
    get admin_client_path(@maria)
    assert_select "#client-timeline li", /Email not delivered.*Quote #{@quote.number} to maria@example.com: The receiving mail server rejected the email/m
    assert_select "#client-timeline a[href=?]", admin_quote_path(@quote)

    notes = as_business(@business) { Notification.where(kind: "email_not_delivered").to_a }
    assert_equal [ "An email to Maria Lopez wasn't delivered" ], notes.map(&:title).uniq
    assert_equal [ "Quote #{@quote.number}: The receiving mail server rejected the email." ], notes.map(&:body).uniq
    assert_equal admin_quote_path(@quote), notes.first.path
  end

  test "Resend is the usual send page; once a resend goes through, the warning and badge go" do
    emailed("bounced")
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem a", "Resend"
    get new_admin_quote_send_path(@quote)
    assert_response :success
    with_fake_pdf_renderer do
      post admin_quote_send_path(@quote), params: { quote_send: { to: "maria.lopez@example.com", subject: "Your quote", message: "Hi" } }
      assert_redirected_to admin_quote_path(@quote)
      perform_enqueued_jobs(only: ClientMailDeliveryJob)
    end
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem", 0
    get admin_quotes_path
    assert_select "#quote-#{@quote.uid} .badge-danger", 0
  end

  test "Resend goes to the send page, which only people who may send can open" do
    emailed("bounced")
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_quote_send_path(@quote) }
  end

  test "each revision's sends say whether they were delivered; an approval on a revision whose email bounced gets a quiet note" do
    emailed("bounced")
    as_business(@business) { @quote.reload.revise!(by: @owner) }
    emailed("bounced")
    link = as_business(@business) { @quote.reload.client_link! }
    as_business(@business) { @quote.reload.record_response!(:approve, link:, signer_name: "Maria Lopez", terms_accepted: "1", device: "Computer · Chrome") }

    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem", 0 # answered: no longer something to act on
    assert_select "#quote-revision-2", /Emailed .* · Not delivered/
    assert_select "#quote-revision-1", /Emailed .* · Not delivered/
    response_uid = as_business(@business) { @quote.approval.uid }
    assert_select "#response-#{response_uid}-undelivered", "The email for this revision wasn't delivered; Maria Lopez reached it from the quote's link."
    get admin_quotes_path
    assert_select "#quote-#{@quote.uid} .badge-danger", 0
  end

  test "a delivered send says so, and no note or warning shows" do
    email = emailed
    as_business(@business) { email.mark!("sent") }
    as_business(@business) { @quote.reload.revise!(by: @owner) }
    emailed.then { |next_email| as_business(@business) { next_email.mark!("sent") } }
    get admin_quote_path(@quote)
    assert_select "#quote-revision-1", /Emailed .* · Sent/
    assert_select "#quote-delivery-problem", 0
  end

  def undelivered_notes = as_business(@business) { Notification.where(kind: "email_not_delivered").to_a }
  def bounce_events = as_business(@business) { ClientEvent.where(kind: "email_bounced").count }

  test "an old email that fails after a later send went out tells nobody; an automation email about the quote does, saying what it was" do
    old = emailed
    emailed("sent", error: nil)
    as_business(@business) { old.mark!("failed", error: "The mail server refused the email (554 5.7.1).", announce: true) }
    assert_empty undelivered_notes
    assert_equal 0, bounce_events
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem", 0

    as_business(@business) do
      EmailMessage.create!(kind: "automated_message", to: "maria@example.com", related: @quote)
                  .mark!("failed", error: "The mail server refused the email (554 5.7.1).", announce: true)
    end
    assert_equal [ "Automated message for Quote #{@quote.number}: The receiving mail server rejected the email." ], undelivered_notes.map(&:body).uniq
    assert_equal 1, bounce_events
  end

  test "marking the same failure twice announces it once" do
    email = emailed
    2.times { as_business(@business) { email.reload.mark!("failed", error: "The mail server refused the email (554 5.7.1).", announce: true) } }
    assert_equal as_business(@business) { @business.business_users.active.count { _1.can?(:office) } }, undelivered_notes.size
    assert_equal 1, bounce_events
  end

  test "a failure on Shadetree's side is reported to operators once, not to the team; the page says it's on our side" do
    { "The mail server refused the email (credentials rejected, 535 5.7.8)." => "535 5.7.8", "The mail server couldn't take the email (OpenTimeout)." => nil,
      "Something went wrong sending this email." => nil }.each do |error, code|
      email = emailed
      reports = capture_error_reports(EmailMessage::UndeliveredOnOurSide) { as_business(@business) { email.mark!("failed", error:, announce: true) } }
      assert_equal 1, reports.size, error
      assert_equal email.id, reports.first.context[:record_id]
      assert_empty undelivered_notes, error
      get admin_quote_path(@quote)
      assert_select "#quote-delivery-problem", /Something went wrong on Shadetree's side, not with the address/
      assert_select "#quote-delivery-problem", /Resend in a while, or send the link yourself/
      assert_select "#quote-delivery-problem .font-mono", code ? code : { count: 0 }
    end
  end

  test "a link copied after the failed email replaces the warning with a quiet note, and the badge goes" do
    emailed("bounced")
    travel 1.minute do
      as_business(@business) { @quote.reload.mark_sent!(by: @owner, channel: "link") }
    end
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem", 0
    assert_select "#quote-link-after-undelivered", /The email to maria@example.com wasn't delivered; the link was copied .* to send yourself/
    get admin_quotes_path
    assert_select "#quote-#{@quote.uid} .badge-danger", 0
  end

  test "an expired quote isn't warned about: it's renewed with a revision" do
    emailed("bounced")
    as_business(@business) { @quote.update_columns(expires_on: @business.today - 1) }
    get admin_quote_path(@quote)
    assert_select "#quote-delivery-problem", 0
    get admin_quotes_path(filter: "expired")
    assert_select "#quote-#{@quote.uid} .badge-danger", 0
  end

  test "an invoice warns the same way, in its page and list" do
    invoice = as_business(@business) do
      invoice = Invoice.start(client: @maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Inspection", "quantity" => "1", "unit_price" => "60" } ])
      invoice.save!
      email = EmailMessage.create!(kind: "invoice_sent", to: "maria@example.com", related: invoice)
      invoice.mark_sent!(by: @owner, channel: "email", recipient: email.to).update!(email_message: email)
      email.mark!("bounced", error: REFUSED)
      invoice
    end
    get admin_invoice_path(invoice)
    assert_select "#invoice-delivery-problem h2", "Email not delivered"
    assert_select "#invoice-delivery-problem", /The invoice is still sent/
    assert_select "#invoice-delivery-problem a[href=?]", new_admin_invoice_send_path(invoice), text: "Resend"
    get admin_invoices_path
    assert_select "#invoice-#{invoice.uid} .badge-danger", "Email not delivered"
    assert_equal [ "Invoice #{invoice.number}: The receiving mail server says this address doesn't exist or can't take email." ],
                 as_business(@business) { Notification.where(kind: "email_not_delivered").map(&:body).uniq }
  end
end
