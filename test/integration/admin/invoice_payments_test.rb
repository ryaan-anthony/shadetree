require "test_helper"

# PAY-05: recording payments against invoices (part and full), overpayment, corrections and
# deletions with reasons, the status and balance they drive, roles and tenancy.
class Admin::InvoicePaymentsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @today = @business.today
    @owner = users(:one)
    @invoice = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      invoice = Invoice.start(client: maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
      invoice.tax_rates = []
      invoice.save!
      invoice.update_columns(status: "sent", sent_at: 1.day.ago)
      invoice
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def fresh = as_business(@business) { @invoice.reload }

  def record(amount, **fields)
    post admin_invoice_payments_path(@invoice), params: { payment: { amount:, received_on: @today.iso8601, payment_method: "check", reference: "1042" }.merge(fields) }
  end

  test "the form defaults to the balance and today; a part payment then the rest make it paid" do
    get admin_invoice_path(@invoice)
    assert_select "a[href=?]", new_admin_invoice_payment_path(@invoice), /Record payment/
    get new_admin_invoice_payment_path(@invoice)
    assert_select "input[name='payment[amount]'][value='200.00']"
    assert_select "input[name='payment[received_on]'][value=?]", @today.iso8601

    record("50", note: "Left in the mailbox")
    assert_redirected_to admin_invoice_path(@invoice)
    assert_match "$150.00 left to pay", flash[:notice]
    assert_equal [ "partially_paid", 5_000, nil ], [ fresh.status, fresh.amount_paid_cents, fresh.paid_at ]
    payment = as_business(@business) { fresh.payments.sole }
    assert_equal [ "check", "1042", "Left in the mailbox", @owner, "recorded" ], [ payment.payment_method, payment.reference, payment.note, payment.recorded_by, payment.source ]

    record("150", payment_method: "cash", reference: "")
    assert_match "paid in full", flash[:notice]
    assert_equal [ "paid", 20_000 ], [ fresh.status, fresh.amount_paid_cents ]
    assert fresh.paid_at
    follow_redirect!
    assert_select "#payment-#{payment.uid}", /Check 1042.*Recorded by .*\$50\.00/m
    assert_select "li", /Payment recorded: \$50\.00, check \(1042\), received/
    assert_select "li", /Paid by/
    assert_select "a[href=?]", new_admin_invoice_payment_path(@invoice), 0, "nothing left to pay"
  end

  test "no method is chosen for them: leaving it out says so and records nothing (owner, 2026-11-22)" do
    get new_admin_invoice_payment_path(@invoice)
    assert_select "select[name='payment[payment_method]'] option[selected]", 0
    assert_select "select[name='payment[payment_method]'] option[value='']", "Choose one"
    record("50", payment_method: "")
    assert_response :unprocessable_content
    assert_select ".field", /Method.*Choose how it was paid\./m
    assert_select "select[name='payment[payment_method]'][aria-invalid=true]"
    assert_equal [ "sent", 0 ], [ fresh.status, fresh.amount_paid_cents ]
    record("50", payment_method: "card")
    assert_select ".field", /That method isn't one staff can record\./

    payment = as_business(@business) { fresh.record_payment!(by: @owner, amount: "50", received_on: @today, payment_method: "cash") }
    get edit_admin_invoice_payment_path(@invoice, payment)
    assert_select "select[name='payment[payment_method]'] option[selected][value=cash]", 1, "a recorded payment keeps its method"
  end

  test "overpayment, a bad amount or date, and paid or void invoices are refused" do
    record("200.01")
    assert_response :unprocessable_content
    assert_select ".field", /more than the amount due \(\$200\.00\)/
    record("0")
    assert_select ".field", /must be more than zero/
    record("abc")
    assert_select ".field", /not a valid amount/
    %w[Infinity NaN -Infinity].each do |amount|
      record(amount)
      assert_select ".field", /not a valid amount/
    end
    record("10", received_on: (@today + 1).iso8601)
    assert_select ".field", /can't be in the future/
    assert_equal [ "sent", 0 ], [ fresh.status, fresh.amount_paid_cents ]

    record("200")
    get new_admin_invoice_payment_path(@invoice)
    assert_match "already paid in full", flash[:alert]
    as_business(@business) { fresh.update_columns(status: "void") }
    record("1")
    assert_match "is void", flash[:alert]
  end

  test "a draft paid on the spot is marked sent and paid; a revision being prepared can't take one" do
    as_business(@business) { @invoice.update_columns(status: "draft", sent_at: nil) }
    get edit_admin_invoice_path(@invoice)
    assert_select "a[href=?]", new_admin_invoice_payment_path(@invoice), /Record a payment/
    get new_admin_invoice_payment_path(@invoice)
    assert_match(/marks invoice #{@invoice.number} as sent/, response.body)
    record("200")
    assert_equal [ "paid", @owner ], [ fresh.status, fresh.sent_by ]
    assert_equal %w[created sent payment_recorded paid], as_business(@business) { fresh.events.map(&:kind) }
    follow_redirect!
    assert_select "li", /Marked sent \(paid on the spot\)/

    as_business(@business) { @invoice.update_columns(status: "draft", revision: 2, amount_paid_cents: 0) }
    get new_admin_invoice_payment_path(@invoice)
    assert_match "Send or discard the changes", flash[:alert]
  end

  test "a recorded payment is changed or deleted with a reason; the status follows and the history keeps it" do
    record("200")
    payment = as_business(@business) { fresh.payments.sole }
    get edit_admin_invoice_payment_path(@invoice, payment)
    assert_select "input[name='payment[amount]'][value='200.00']"

    patch admin_invoice_payment_path(@invoice, payment), params: { payment: { amount: "120" }, reason: "" }
    assert_response :unprocessable_content
    assert_select "#payment_change_reason_error", /Say why/
    assert_equal 20_000, fresh.amount_paid_cents

    patch admin_invoice_payment_path(@invoice, payment), params: { payment: { amount: "250" }, reason: "Typo" }
    assert_select ".field", /more than the balance \(\$200\.00\)/

    patch admin_invoice_payment_path(@invoice, payment), params: { payment: { amount: "120" }, reason: "Typed the wrong amount" }
    assert_redirected_to admin_invoice_path(@invoice)
    assert_equal [ "partially_paid", 12_000, nil ], [ fresh.status, fresh.amount_paid_cents, fresh.paid_at ]
    follow_redirect!
    assert_select "li", /Payment changed: \$200\.00, check \(1042\), received .* → \$120\.00, check \(1042\), received .*“Typed the wrong amount”/
    assert_select "li", /Partly paid/

    delete admin_invoice_payment_path(@invoice, payment), params: { reason: "  " }
    assert_select "#payment_delete_reason[aria-invalid=true]"
    assert_select "#payment_delete_reason_error", /Say why/
    assert_select "#payment_change_reason_error", 0
    delete admin_invoice_payment_path(@invoice, payment), params: { reason: "Check bounced" }
    assert_equal [ "sent", 0 ], [ fresh.status, fresh.amount_paid_cents ]
    assert_empty as_business(@business) { fresh.payments.to_a }
    follow_redirect!
    assert_select "li", /Payment deleted: \$120\.00, check \(1042\), .*“Check bounced”/
    assert_select "li", /Awaiting payment again/
  end

  test "online payments are listed but can't be changed here" do
    online = as_business(@business) do
      @invoice.payments.create!(business: @business, currency: "USD", source: "online", payment_method: "card", amount: "80", received_on: @today).tap { @invoice.apply_payments! }
    end
    get admin_invoice_path(@invoice)
    assert_select "#payment-#{online.uid}", /Card.*Paid online/m
    assert_select "a[href=?]", edit_admin_invoice_payment_path(@invoice, online), 0
    delete admin_invoice_payment_path(@invoice, online), params: { reason: "No" }
    assert_redirected_to admin_invoice_path(@invoice)
    assert_equal 8_000, fresh.amount_paid_cents
  end

  test "paying in full gives the client's link a year; reopening takes it away" do
    link = as_business(@business) { @invoice.client_link! }
    assert_nil link.expires_at
    record("200")
    assert_in_delta 1.year.from_now, as_business(@business) { link.reload.expires_at }, 1.minute
    payment = as_business(@business) { fresh.payments.sole }
    delete admin_invoice_payment_path(@invoice, payment), params: { reason: "Check bounced" }
    assert_nil as_business(@business) { link.reload.expires_at }
  end

  test "technicians can't record or change payments; other businesses' invoices and payments are out of reach" do
    record("50")
    payment = as_business(@business) { fresh.payments.sole }
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_invoice_payment_path(@invoice) }
    assert_permission_matrix(technician: false) { record("1") }
    assert_permission_matrix(technician: false) { delete admin_invoice_payment_path(@invoice, payment), params: { reason: "x" } }
    assert_permission_matrix(technician: false) { get edit_admin_invoice_payment_path(@invoice, payment) }
    assert_permission_matrix(technician: false) { patch admin_invoice_payment_path(@invoice, payment), params: { payment: { amount: "1" }, reason: "x" } }

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    theirs, their_payment = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      invoice = Invoice.start(client:)
      invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "10" } ])
      invoice.save!
      invoice.update_columns(status: "sent", sent_at: Time.current)
      [ invoice, invoice.payments.create!(business: invoice.business, currency: "USD", payment_method: "cash", amount: "5", received_on: Date.current) ]
    end
    assert_not_found_across_businesses { get new_admin_invoice_payment_path(theirs) }
    assert_not_found_across_businesses { post admin_invoice_payments_path(theirs), params: { payment: { amount: "1" } } }
    assert_not_found_across_businesses { get edit_admin_invoice_payment_path(@invoice, their_payment) }
    assert_not_found_across_businesses { delete admin_invoice_payment_path(@invoice, their_payment), params: { reason: "x" } }

    # Another invoice's payment, in the same business.
    other = as_business(@business) do
      Invoice.start(client: @invoice.client).tap do |invoice|
        invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "10" } ])
        invoice.save!
      end
    end
    get edit_admin_invoice_payment_path(other, payment)
    assert_response :not_found
    delete admin_invoice_payment_path(other, payment), params: { reason: "x" }
    assert_response :not_found
    assert_equal 5_000, fresh.amount_paid_cents
  end
end
