require "test_helper"

# QTE-04: sending a quote by email or as a copied link.
class Admin::QuoteSendsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      quote = Quote.start(client: maria)
      quote.title = "Spring cleanup"
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180", "taxable" => "0" } ])
      quote.save!
      quote
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def fresh = as_business(@business) { @quote.reload }
  def usage_count = as_business(@business) { UsageEvent.where(subject: @quote).count }

  def send_email(**fields)
    post admin_quote_send_path(@quote), params: { quote_send: { to: "maria@example.com", subject: "Your quote", message: "Hi Maria" }.merge(fields) }
  end

  test "the send page prefills the client's email, the subject and a message" do
    get new_admin_quote_send_path(@quote)
    assert_response :success
    assert_select "input[name='quote_send[to]'][value='maria@example.com']"
    assert_select "input[name='quote_send[subject]'][value=?]", "Quote #{@quote.number} from #{@business.name}: Spring cleanup"
    assert_select "textarea[name='quote_send[message]']", /Hi Maria,/
    assert_select "form[action=?] button", admin_quote_send_path(@quote), /Get the link/
  end

  test "sending by email freezes the quote, records the send and usage once, and emails the client" do
    with_fake_pdf_renderer do
      send_email(cc: "partner@example.com")
      assert_redirected_to admin_quote_path(@quote)

      quote = fresh
      assert_equal "sent", quote.status
      assert_equal users(:one), quote.sent_by
      assert quote.sent_at
      assert_not quote.editable?
      send = as_business(@business) { quote.sends.first }
      assert_equal [ "email", "maria@example.com", "partner@example.com", users(:one) ], [ send.channel, send.recipient, send.cc, send.user ]
      assert_equal 1, usage_count

      perform_enqueued_jobs
      mail = ActionMailer::Base.deliveries.last
      assert_equal [ [ "maria@example.com" ], [ "partner@example.com" ], "Your quote" ], [ mail.to, mail.cc, mail.subject ]
      assert_equal "Quote #{quote.number}.pdf", mail.attachments.first.filename
      link = as_business(@business) { ClientLink.active.find_by!(linkable: quote) }
      assert_match "/c/#{link.token}", mail.html_part.body.to_s
      assert_match "Hi Maria", mail.text_part.body.to_s
      assert_equal "sent", as_business(@business) { send.reload.email_message.status }

      get edit_admin_quote_path(@quote)
      assert_redirected_to admin_quotes_path
    end
  end

  test "sending again records another send, but no new usage" do
    with_fake_pdf_renderer do
      send_email
      sent_at = fresh.sent_at
      travel 1.hour do
        send_email(to: "maria.lopez@example.com")
      end
      assert_equal sent_at, fresh.sent_at
      assert_equal 2, as_business(@business) { @quote.sends.count }
      assert_equal 1, usage_count
      get admin_quote_path(@quote)
      assert_select "#sent-panel-h", /Sent/
      assert_select "li", /Emailed to maria.lopez@example.com/
    end
  end

  test "copy link marks the quote sent and counts once; the page then shows the link to copy" do
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_redirected_to new_admin_quote_send_path(@quote)
    assert_equal "sent", fresh.status
    assert_equal [ "link" ], as_business(@business) { @quote.sends.pluck(:channel) }
    assert_equal 1, usage_count
    follow_redirect!
    link = as_business(@business) { ClientLink.active.find_by!(linkable: @quote) }
    assert_select "input[value=?][data-clipboard-target=source]", client_link_url(link.token)
    assert_no_enqueued_emails
  end

  test "a bad, missing or refused address is a clear error and nothing is sent" do
    send_email(to: "not-an-email")
    assert_response :unprocessable_content
    assert_select ".field", /isn't a valid email address/
    send_email(to: "")
    assert_select ".field", /add the client's email address/
    send_email(cc: "a@example.com, nope")
    assert_select ".field", /isn't valid: nope/
    as_business(@business) { EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce") }
    send_email
    assert_select ".field", /was refused by the mail server before/
    assert_equal "draft", fresh.status
    assert_equal 0, usage_count
    assert_no_enqueued_emails
  end

  test "an empty draft can't be sent" do
    as_business(@business) { @quote.line_items.delete_all }
    get new_admin_quote_send_path(@quote)
    assert_redirected_to edit_admin_quote_path(@quote)
    assert_equal "Add at least one line before sending.", flash[:alert]
  end

  test "an unconfirmed account can see the page but can't send" do
    unconfirmed = users(:unconfirmed)
    BusinessUser.create!(user: unconfirmed, business: @business, role: "admin", active: true)
    sign_in unconfirmed
    post switch_admin_business_path, params: { business: @business.uid }
    get new_admin_quote_send_path(@quote)
    assert_select ".banner-warning", /Confirm your email address/
    send_email
    assert_match "Confirm your email address", flash[:alert]
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "draft", fresh.status
    assert_equal 0, usage_count
  end

  test "technicians can't send; other businesses' quotes aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_quote_send_path(@quote) }

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      Quote.start(client: Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ]))
    end
    assert_not_found_across_businesses { get new_admin_quote_send_path(theirs) }
    assert_not_found_across_businesses { post admin_quote_send_path(theirs), params: { channel: "link" } }
  end

  test "a delivery problem shows on the quote and in the list" do
    with_fake_pdf_renderer do
      send_email
      as_business(@business) { @quote.sends.first.email_message.mark!("bounced", error: "The mail server refused this address (550 5.1.1).") }
      get admin_quote_path(@quote)
      assert_select "#quote-delivery-problem", /wasn't delivered: The mail server refused this address/
      get admin_quotes_path
      assert_select "#quote-#{@quote.uid}", /Not delivered/
    end
  end

  test "a quote can be emailed at most five times a day" do
    with_fake_pdf_renderer do
      5.times { |i| send_email(to: "maria#{i}@example.com") }
      send_email
      assert_response :unprocessable_content
      assert_select "[role=alert]", /emailed 5 times today/
      assert_equal 5, as_business(@business) { @quote.sends.count }
      travel(25.hours) do
        send_email
        assert_redirected_to admin_quote_path(@quote)
      end
    end
  end

  test "a CC the mail server refused before is an error too" do
    as_business(@business) { EmailSuppression.suppress!("old@example.com", reason: "hard_bounce") }
    send_email(cc: "ok@example.com, old@example.com")
    assert_response :unprocessable_content
    assert_select ".field", /includes old@example.com, which the mail server refused before/
  end

  test "an expired quote can't be sent until its date is moved" do
    as_business(@business) { @quote.update_columns(expires_on: @business.today - 1) }
    get new_admin_quote_send_path(@quote)
    assert_redirected_to edit_admin_quote_path(@quote)
    assert_match "Change its valid-until date before sending", flash[:alert]
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "draft", fresh.status
    assert_equal 0, usage_count
  end

  test "a PDF that can't be made yet is retried, not failed" do
    with_fake_pdf_renderer(fail_with: PdfRenderer::Error.new("PDF renderer busy")) do
      send_email
      perform_enqueued_jobs
      assert_enqueued_jobs 1, only: ClientMailDeliveryJob
      assert_equal "queued", as_business(@business) { @quote.sends.first.email_message.status }
    end
  end

  test "a refused message with CCs blames no address" do
    with_fake_pdf_renderer do
      send_email(cc: "partner@example.com")
      FakeSmtpServer.run(rcpt: "550 5.1.1 no such user") do |settings|
        previous = [ QuoteMailer.delivery_method, QuoteMailer.smtp_settings ]
        QuoteMailer.delivery_method = :smtp
        QuoteMailer.smtp_settings = settings
        perform_enqueued_jobs
      ensure
        QuoteMailer.delivery_method, QuoteMailer.smtp_settings = previous
      end
      email = as_business(@business) { @quote.sends.first.email_message }
      assert_equal [ "bounced", "The mail server refused one of the addresses (550 5.1.1)." ], [ email.status, email.error ]
      assert_not as_business(@business) { EmailSuppression.suppressed?("maria@example.com") }
    end
  end

  test "the client's address and the note stay out of the request log" do
    logged = StringIO.new
    previous, Rails.logger = Rails.logger, ActiveSupport::Logger.new(logged)
    ActionController::Base.logger = Rails.logger
    with_fake_pdf_renderer { send_email(message: "Gate code 4321") }
    assert_match "[FILTERED]", logged.string
    assert_no_match "maria@example.com", logged.string
    assert_no_match "Gate code", logged.string
  ensure
    Rails.logger = ActionController::Base.logger = previous
  end

  test "a resend after a delivery problem clears the warning once it goes through" do
    with_fake_pdf_renderer do
      send_email
      as_business(@business) { @quote.sends.first.email_message.mark!("bounced", error: "refused") }
      send_email(to: "maria.lopez@example.com")
      perform_enqueued_jobs
      get admin_quote_path(@quote)
      assert_select "#quote-delivery-problem", 0
      get admin_quotes_path
      assert_no_match "Not delivered", response.body
    end
  end

  test "an emailed link has at least a month left; a revoked one is replaced before sending" do
    with_fake_pdf_renderer do
      old = as_business(@business) { @quote.update_column(:status, "sent"); ClientLink.issue!(@quote, expires_at: 10.days.from_now) }
      send_email
      link = as_business(@business) { ClientLink.active.where(linkable: @quote).order(:created_at).last }
      assert_not_equal old, link
      assert_operator link.expires_at, :>, 30.days.from_now
      as_business(@business) { link.revoke! }
      perform_enqueued_jobs
      body = ActionMailer::Base.deliveries.last.text_part.body.to_s
      assert_no_match link.token, body
      assert_match %r{/c/\w{32}}, body
      assert_no_match "<time", body, "the plain-text part has no HTML"
    end
  end

  test "an unconfirmed account doesn't see a sent quote's link" do
    as_business(@business) { @quote.mark_sent!(by: users(:one), channel: "link") }
    link = as_business(@business) { @quote.client_link! }
    unconfirmed = users(:unconfirmed)
    BusinessUser.create!(user: unconfirmed, business: @business, role: "admin", active: true)
    sign_in unconfirmed
    post switch_admin_business_path, params: { business: @business.uid }
    get new_admin_quote_send_path(@quote)
    assert_no_match link.token, response.body
    assert_select "p", /Confirm your email address to see the link/
  end
end
