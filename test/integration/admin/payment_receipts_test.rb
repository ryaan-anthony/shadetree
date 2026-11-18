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

  test "ticking the box emails the client a receipt with what's left; it shows on the payment" do
    get new_admin_invoice_payment_path(@invoice)
    assert_select "input[type=checkbox][name=send_receipt]:not([checked])"
    assert_select "label", /Email a receipt to maria@example.com/

    record("50")
    assert_match "Receipt on its way to maria@example.com", flash[:notice]
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ [ "maria@example.com" ], "Payment received for invoice #{@invoice.number} from #{@business.name}" ], [ mail.to, mail.subject ]
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
    assert_no_match(/receipt/i, flash[:notice])
    assert_no_enqueued_emails
  end
end
