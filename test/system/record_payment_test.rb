require "application_system_test_case"

# PAY-05 (owner, 2026-11-22): recording a payment has no method chosen for you, so the browser
# asks for one, and "Email a receipt" starts ticked.
class RecordPaymentSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @invoice = Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      job = Job.create!(client:, title: "Ants", line_items_attributes: [ { name: "Spraying", quantity: 1, unit_price: 40 } ])
      Invoice.from_job!(job.tap { _1.complete!(by: users(:one)) }, by: users(:one)).tap { _1.mark_sent!(by: users(:one), channel: "link") }
    end
    visit new_user_session_path
    sign_in_with_form(users(:one).email)
    assert_text "Home"
  end

  test "a method must be chosen; the receipt goes unless they untick it" do
    visit new_admin_invoice_payment_path(@invoice)
    assert_select "Method", selected: "Choose one"
    assert_checked_field "Email a receipt to maria@example.com"
    click_on "Record payment"
    assert_selector "h1", text: "Record a payment"
    assert_current_path new_admin_invoice_payment_path(@invoice)
    assert_not_empty find_field("Method").native.property("validationMessage"), "the browser asks for a method"
    assert_equal 0, Tenancy.with_business(@business) { @invoice.payments.count }

    select "Cash", from: "Method"
    click_on "Record payment"
    assert_text "is paid in full. Receipt on its way to maria@example.com."
    assert_equal [ "cash" ], Tenancy.with_business(@business) { @invoice.payments.pluck(:payment_method) }
  end
end
