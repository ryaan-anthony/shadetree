require "test_helper"

# PAY-04: a client pays an invoice from its link through Stripe Checkout on the business's own
# account: the balance or (when allowed) a part of it; abandoned or failed starts change nothing;
# and nobody can pay when the business can't take payments, the client was erased or the
# business is suspended.
class Client::InvoicePaymentsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @gateway = use_fake_payment_gateway
    @invoice = as_business(@business) do
      @account = PaymentAccount.create!(account_id: "acct_test1", details_submitted: true, charges_enabled: true, payouts_enabled: true)
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      invoice = Invoice.start(client: maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
      invoice.tax_rates = []
      invoice.save!
      invoice.mark_sent!(by: users(:one), channel: "link")
      invoice
    end
    @link = as_business(@business) { @invoice.client_link! }
  end

  def session_params = @gateway.calls_to(:create_checkout_session).last&.dig(2)

  test "the client pays the balance on Stripe Checkout and comes back to a thank-you page" do
    get client_link_path(@link.token)
    assert_select "#pay-button", /Pay \$200\.00/
    assert_select "#pay_amount", false, "part payments are off by default"
    assert_match %r{form-action 'self' https://checkout\.stripe\.com}, response.headers["Content-Security-Policy"]

    post client_invoice_pay_path(@link.token)
    assert_response :see_other
    assert_match %r{\Ahttps://checkout\.stripe\.com/c/pay/cs_test_}, response.location
    _, account_id, params = @gateway.calls_to(:create_checkout_session).last
    assert_equal "acct_test1", account_id, "a direct charge on the business's account"
    assert_equal 20_000, params[:line_items].first[:price_data][:unit_amount]
    assert_equal "#{client_invoice_paid_url(@link.token)}?session={CHECKOUT_SESSION_ID}", params[:success_url]
    assert_equal client_link_url(@link.token, payment: "cancelled"), params[:cancel_url]
    assert_equal "sent", as_business(@business) { @invoice.reload.status }, "nothing is recorded until Stripe confirms it"

    get client_invoice_paid_path(@link.token, session: "cs_test_1")
    assert_select "#payment-thanks", /will show it in a moment/
    as_business(@business) { @invoice.record_online_payment!(intent_id: "pi_1", amount_cents: 20_000, currency: "usd", checkout_id: "cs_test_1", method_detail: "Visa ending 4242") }
    get client_invoice_paid_path(@link.token, session: "cs_test_1")
    assert_select "#payment-thanks", /\$200\.00 paid on invoice .* with Visa ending 4242.*paid in full/m
    get client_link_path(@link.token)
    assert_select "#pay-button", false
  end

  test "coming back without paying, or Stripe failing, leaves the invoice as it was with a way to try again" do
    get client_link_path(@link.token, payment: "cancelled")
    assert_select "#payment-cancelled", /nothing was charged/
    assert_select "#pay-button"

    @gateway.fail_next!
    post client_invoice_pay_path(@link.token)
    assert_redirected_to client_link_path(@link.token)
    assert_match "nothing was charged", flash[:alert]
    assert_equal [ "sent", 0 ], as_business(@business) { @invoice.reload.then { [ _1.status, _1.amount_paid_cents ] } }
  end

  test "with part payments allowed the client picks an amount between the minimum and the balance" do
    @business.update!(online_partial_payments: true)
    get client_link_path(@link.token)
    assert_select "#pay_amount[value=?]", "200.00"
    assert_select "#pay_amount_help", /From \$1\.00 up to \$200\.00/

    post client_invoice_pay_path(@link.token), params: { amount: "75.50" }
    assert_equal 7_550, session_params[:line_items].first[:price_data][:unit_amount]
    [ "0.50", "200.01", "lots" ].each do |amount|
      post client_invoice_pay_path(@link.token), params: { amount: }
      assert_redirected_to client_link_path(@link.token)
      assert_match(/Enter an amount/, flash[:alert], amount)
    end
    assert_equal 1, @gateway.calls_to(:create_checkout_session).size

    @business.update!(online_partial_payments: false)
    post client_invoice_pay_path(@link.token), params: { amount: "10" }
    assert_equal 20_000, session_params[:line_items].first[:price_data][:unit_amount], "the full balance when part payments are off"
  end

  test "no Pay when the account can't take charges, it's disconnected, or the invoice is paid or void" do
    as_business(@business) { @account.update!(charges_enabled: false) }
    get client_link_path(@link.token)
    assert_select "#pay-button", false
    post client_invoice_pay_path(@link.token)
    assert_match "can't be paid online", flash[:alert]

    as_business(@business) { @account.update!(charges_enabled: true, disconnected_at: Time.current, disconnected_reason: "owner") }
    get client_link_path(@link.token)
    assert_response :success
    assert_select "#pay-button", false
    assert_empty @gateway.calls_to(:create_checkout_session)
  end

  test "an erased client can't pay (INS-02), and a suspended business's links are unavailable (OPS-04)" do
    as_business(@business) { @invoice.client.update_columns(erased_at: Time.current) }
    post client_invoice_pay_path(@link.token)
    assert_match "can't be paid online", flash[:alert]

    as_business(@business) { @invoice.client.update_columns(erased_at: nil) }
    @business.suspend!(reason: "testing")
    post client_invoice_pay_path(@link.token)
    assert_response :gone
    assert_empty @gateway.calls_to(:create_checkout_session)
  end

  test "the staff preview shows the Pay button without a working form" do
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get preview_admin_invoice_path(@invoice)
    assert_select "#pay [aria-disabled=true]", /Pay \$200\.00/
    assert_select "#pay form", false
  end

  test "owners and admins choose part payments, and see the platform fee only when there is one" do
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_payment_account_path
    assert_select "#platform-fee", /Stripe's card fees apply/
    assert_select "#platform-fee", { text: /Shadetree's fee/, count: 0 }
    patch admin_payment_account_path, params: { business: { online_partial_payments: "1" } }
    assert @business.reload.online_partial_payments?
    @business.plan.update!(platform_fee_bps: 50)
    get admin_payment_account_path
    assert_select "#platform-fee", /Shadetree's fee is 0\.5% of each online payment/
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch admin_payment_account_path, params: { business: { online_partial_payments: "0" } } }
  end
end
