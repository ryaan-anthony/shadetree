require "test_helper"

# QTE-05: the client approves, declines or asks for changes through their link.
class Client::QuoteResponsesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client: maria)
      quote.title = "Spring cleanup"
      quote.terms = "Net 15."
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "2", "unit_price" => "90", "taxable" => "0" } ])
      quote.save!
      quote.mark_sent!(by: users(:one), channel: "link")
      quote
    end
    @link = as_business(@business) { @quote.client_link! }
  end

  def fresh = as_business(@business) { @quote.reload }
  def responses = as_business(@business) { @quote.responses.to_a }

  def approve(name: "Maria Lopez", terms: "1", version: fresh.lock_version, **extra)
    post approve_client_quote_path(@link.token), params: { version:, quote_response: { signer_name: name, terms_accepted: terms, **extra } },
                                                 headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1" }
  end

  test "an open quote offers approve, decline and ask for changes" do
    get client_link_path(@link.token)
    assert_select "#quote-actions button", "Approve quote"
    assert_select "#quote-actions button", "Decline quote"
    assert_select "#quote-actions button", "Ask for changes"
    assert_select "form[action=?] input[name=version][value=?]", approve_client_quote_path(@link.token), fresh.lock_version.to_s
    # No email on file: the approve form offers one for the copy.
    assert_select "form[action=?] input[name='quote_response[email]']", approve_client_quote_path(@link.token)
  end

  test "approving records the signer, evidence and a snapshot of exactly what was approved" do
    version = fresh.lock_version
    with_fake_pdf_renderer do
      approve(email: "Maria@Example.com")
      assert_redirected_to client_link_path(@link.token)
      follow_redirect!
      assert_select ".banner-success", /Thanks, Maria Lopez\. You're all set\..*will be in touch to schedule the work/m
      assert_select "a", /Download approved PDF/

      quote = fresh
      assert_equal "approved", quote.status
      assert_not quote.editable?
      approval = responses.sole
      assert_equal [ "approved", "Maria Lopez", "maria@example.com", @link.id, nil, version ],
                   [ approval.kind, approval.signer_name, approval.email, approval.client_link_id, approval.recorded_by_id, approval.quote_version ]
      assert_equal "127.0.0.1", approval.ip_address
      assert_match "iPhone", approval.user_agent
      assert approval.device.present?
      assert_equal 18_000, approval.snapshot.dig("totals", "total_cents")
      assert_equal [ "Leaf cleanup", "2.0", 9_000 ], approval.snapshot["lines"].sole.values_at("name", "quantity", "unit_price_cents")
      assert_equal "Net 15.", approval.snapshot["terms"]
      assert approval.snapshot_intact?
      assert_raises(ActiveRecord::ReadOnlyRecord) { approval.update!(signer_name: "Someone else") }

      # The owner hears about it; Maria gets a confirmation with the approved PDF at the email she gave.
      perform_enqueued_jobs
      team = ActionMailer::Base.deliveries.find { _1.to == [ users(:one).email ] }
      assert_equal "Maria Lopez approved quote #{quote.number}", team.subject
      assert_match "Signed by", team.text_part.body.to_s
      client = ActionMailer::Base.deliveries.find { _1.to == [ "maria@example.com" ] }
      assert_equal "You approved quote #{quote.number} from #{@business.name}", client.subject
      assert_equal "Quote #{quote.number}.pdf", client.attachments.sole.filename
      assert_equal "quote_approved", as_business(@business) { quote.email_messages.find_by!(to: "maria@example.com").kind }
    end
  end

  test "the approved PDF shows who signed, when, and the approval reference" do
    approve
    approval = responses.sole
    html = as_business(@business) { fresh.pdf_html }
    assert_match(/Signed by\s*<strong>Maria Lopez<\/strong>/, html)
    assert_match "Approval reference #{approval.reference}", html
  end

  test "the approval record is signed: editing it in the database alone is detectable" do
    approve
    approval = responses.sole
    assert as_business(@business) { approval.signature_valid? }
    as_business(@business) { QuoteResponse.where(id: approval.id).update_all(signer_name: "Someone else") }
    assert_not as_business(@business) { approval.reload.signature_valid? }
  end

  test "an email on file wins over a typed one" do
    as_business(@business) { @quote.client.contact_methods.create!(kind: "email", value: "maria@example.com") }
    get client_link_path(@link.token)
    assert_select "input[name='quote_response[email]']", false
    approve(email: "someone@elsewhere.example")
    perform_enqueued_jobs
    assert_nil responses.sole.email
    assert_empty ActionMailer::Base.deliveries.select { _1.to == [ "someone@elsewhere.example" ] }
    assert_equal "maria@example.com", as_business(@business) { fresh.email_messages.sole.to }
  end

  test "the confirmation counts toward the business's hourly client email limit" do
    as_business(@business) do
      EmailMessage::CLIENT_EMAILS_PER_HOUR.times { EmailMessage.create!(kind: "quote_sent", to: "x#{_1}@example.com") }
    end
    approve(email: "maria@example.com")
    assert_equal "approved", fresh.status
    assert_empty as_business(@business) { fresh.email_messages.to_a }
  end

  test "the client's words reach the team as text, never as links or images" do
    post request_changes_client_quote_path(@link.token),
         params: { quote_response: { message: %(Call me <a href="https://evil.example">here</a> <img src="https://evil.example/p.gif">) } }
    perform_enqueued_jobs
    html = ActionMailer::Base.deliveries.sole.html_part.body.to_s
    assert_no_match(/<a href="https:\/\/evil/, html)
    assert_no_match(/<img src="https:\/\/evil/, html)
    assert_match "&lt;a href=", html
  end

  test "approving needs a name and agreement to the terms" do
    approve(name: " ", terms: "0")
    assert_response :unprocessable_content
    assert_select "[data-modal-open-value=true] #quote-approve"
    assert_select "#quote-approve", /Type your full name to sign\..*Confirm that you agree to the quote and its terms\./m
    assert_equal "sent", fresh.status
    assert_empty responses
  end

  test "a double tap or a second device approves once" do
    approve
    approve(version: fresh.lock_version)
    assert_redirected_to client_link_path(@link.token)
    assert_equal "This quote has already been answered.", flash[:alert]

    other = as_business(@business) { ClientLink.issue!(@quote, actions: Quote::CLIENT_ACTIONS) }
    post approve_client_quote_path(other.token), params: { version: fresh.lock_version, quote_response: { signer_name: "M", terms_accepted: "1" } }
    assert_equal "This quote has already been answered.", flash[:alert]
    assert_equal 1, responses.size
  end

  test "a page opened before the quote changed can't approve it" do
    approve(version: fresh.lock_version - 1)
    assert_equal "This quote was updated after you opened it. Check this version, then approve again.", flash[:alert]
    approve(version: nil)
    assert_equal "sent", fresh.status
  end

  test "declining takes an optional reason and keeps the quote viewable" do
    post decline_client_quote_path(@link.token), params: { quote_response: { message: "" } }
    assert_redirected_to client_link_path(@link.token)
    assert_equal "declined", fresh.status
    assert_nil responses.sole.message
    get client_link_path(@link.token)
    assert_response :success
    assert_select ".banner", /You declined this quote/
    assert_select "#quote-actions form", false
  end

  test "asking for changes needs a message, and the team gets it" do
    post request_changes_client_quote_path(@link.token), params: { quote_response: { message: " " } }
    assert_response :unprocessable_content
    assert_select "[data-modal-open-value=true] #quote-request-changes", /Say what you'd like changed\./

    post request_changes_client_quote_path(@link.token), params: { quote_response: { message: "Can you skip the side yard?" } }
    assert_equal "changes_requested", fresh.status
    assert_equal "Can you skip the side yard?", responses.sole.message
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.sole
    assert_equal "Maria Lopez asked for changes to quote #{@quote.number}", mail.subject
    assert_match "Can you skip the side yard?", mail.html_part.body.to_s

    # Answered: nothing more from this page until a new version is sent.
    post approve_client_quote_path(@link.token), params: { version: fresh.lock_version, quote_response: { signer_name: "Maria", terms_accepted: "1" } }
    assert_equal "This quote has already been answered.", flash[:alert]
  end

  test "an expired quote can't be answered" do
    as_business(@business) { @quote.update_columns(expires_on: @business.today - 1) }
    approve
    assert_equal "This quote has expired, so it can't be approved as is.", flash[:alert]
    post decline_client_quote_path(@link.token)
    assert_equal "This quote has expired. Ask for an updated one below.", flash[:alert]
    assert_equal "sent", fresh.status
    assert_empty responses
  end

  test "only links that allow answering can answer, and only while active" do
    view_only = as_business(@business) { ClientLink.issue!(@quote) }
    post approve_client_quote_path(view_only.token), params: { version: fresh.lock_version, quote_response: { signer_name: "M", terms_accepted: "1" } }
    assert_match "can't be used to answer", flash[:alert]

    @link.revoke!
    approve
    assert_response :gone
    assert_empty responses
  end

  test "a draft is never reachable" do
    draft = as_business(@business) { Quote.start(client: @quote.client) }
    link = as_business(@business) { ClientLink.issue!(draft, actions: Quote::CLIENT_ACTIONS) }
    post approve_client_quote_path(link.token), params: { quote_response: { signer_name: "M", terms_accepted: "1" } }
    assert_response :not_found
  end

  test "the staff preview shows the buttons but can't act" do
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get preview_admin_quote_path(@quote)
    assert_select "#quote-actions button[disabled]", 3
    assert_select "#quote-actions form", false
  end

  test "the next-steps text comes from settings" do
    @business.update!(quote_approved_message: "We'll call within two days to book you in.")
    approve
    follow_redirect!
    assert_select ".banner-success", /We'll call within two days to book you in\./
  end
end
