require "test_helper"

# PAY-05: the optional receipt for a recorded payment.
class Admin::PaymentReceiptsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @invoice = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      invoice = Invoice.start(client: maria)
      invoice.title = "Spring cleanup"
      invoice.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
      invoice.tax_rates = []
      invoice.save!
      invoice.update_columns(status: "sent", sent_at: 1.day.ago)
      invoice
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def record(amount, receipt: "1")
    post admin_invoice_payments_path(@invoice), params: { send_receipt: receipt,
                                                          payment: { amount:, received_on: @business.today.iso8601, payment_method: "check", reference: "1042" } }
  end

  test "a receipt comes from the invoice's location (CAT-07)" do
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    as_business(@business) do
      north = Location.create!(name: "North yard", email: "north@example.com", phone: "555-0177")
      @invoice.update_columns(location_id: north.id)
    end
    perform_enqueued_jobs { record("50") }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "north@example.com" ], mail.reply_to
    assert_includes mail.text_part.body.to_s, "North yard"
  end

  test "the box is ticked to start with; after a mistake it stays as they left it (owner, 2026-11-22)" do
    get new_admin_invoice_payment_path(@invoice)
    assert_select "input[type=checkbox][name=send_receipt][checked]"

    post admin_invoice_payments_path(@invoice), params: { payment: { amount: "50", received_on: @business.today.iso8601, payment_method: "" } }
    assert_response :unprocessable_content
    assert_select "input[type=checkbox][name=send_receipt]:not([checked])", 1, "unticked, it stays unticked"
    post admin_invoice_payments_path(@invoice), params: { send_receipt: "1", payment: { amount: "50", received_on: @business.today.iso8601, payment_method: "" } }
    assert_select "input[type=checkbox][name=send_receipt][checked]"
    assert_no_enqueued_emails
  end

  test "ticking the box emails the client a receipt with what's left; it shows on the payment" do
    get new_admin_invoice_payment_path(@invoice)
    assert_select "label", /Email a receipt to maria@example.com/

    record("50")
    assert_match "Receipt on its way to maria@example.com", flash[:notice]
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ [ "maria@example.com" ], "Receipt for invoice #{@invoice.number} from #{@business.name}" ], [ mail.to, mail.subject ]
    body = mail.html_part.body.to_s
    assert_match "$50.00", body
    assert_match "Check 1042", body
    assert_match "$150.00 left to pay", body
    link = as_business(@business) { ClientLink.active.find_by!(linkable: @invoice) }
    assert_match "/c/#{link.token}", body
    assert_match "Paid in full", ActionMailer::Base.deliveries.tap { record("150"); perform_enqueued_jobs }.last.text_part.body.to_s

    get admin_invoice_path(@invoice)
    assert_select "li", /Receipt to maria@example.com: sent/
  end

  test "no receipt unless asked, for a client without an email, to a refused address, or from an unconfirmed account" do
    record("10", receipt: "0")
    assert_no_match "Receipt", flash[:notice]
    as_business(@business) { EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce") }
    record("10")
    assert_match "No receipt sent: the mail server refused maria@example.com before", flash[:notice]
    assert_no_enqueued_emails

    unconfirmed = users(:unconfirmed)
    BusinessUser.create!(user: unconfirmed, business: @business, role: "admin", active: true)
    sign_in unconfirmed
    post switch_admin_business_path, params: { business: @business.uid }
    get new_admin_invoice_payment_path(@invoice)
    assert_select "input[name=send_receipt]", 0
    as_business(@business) { EmailSuppression.where(email: "maria@example.com").delete_all }
    record("10")
    assert_match "confirm your email address first", flash[:notice]
    assert_no_enqueued_emails
  end

  test "each receipt says what was left after its payment; one for a deleted payment isn't sent" do
    record("50")
    record("150", receipt: "0")
    perform_enqueued_jobs
    assert_match "$150.00 left to pay", ActionMailer::Base.deliveries.last.text_part.body.to_s

    ActionMailer::Base.deliveries.clear
    as_business(@business) { @invoice.reload.payments.each { |payment| @invoice.delete_payment!(payment, by: users(:one), reason: "Test") } }
    record("20")
    payment = as_business(@business) { @invoice.reload.payments.last }
    as_business(@business) { @invoice.delete_payment!(payment, by: users(:one), reason: "Wrong invoice") }
    perform_enqueued_jobs
    assert_empty ActionMailer::Base.deliveries
    email = as_business(@business) { EmailMessage.where(kind: "payment_receipt").order(:id).last }
    assert_equal [ "failed", "The payment was deleted before the receipt went out." ], [ email.status, email.error ]
  end

  test "receipts stop at five a day per client, and at the business's hourly cap" do
    as_business(@business) { 5.times { EmailMessage.create!(kind: "payment_receipt", to: "maria@example.com") } }
    record("10")
    assert_match "has had 5 receipts today", flash[:notice]
    as_business(@business) { EmailMessage.delete_all; EmailMessage::CLIENT_EMAILS_PER_HOUR.times { EmailMessage.create!(kind: "quote_sent", to: "x@example.com") } }
    record("10")
    assert_match "a lot of emails in an hour", flash[:notice]
    assert_no_enqueued_emails
  end
end
