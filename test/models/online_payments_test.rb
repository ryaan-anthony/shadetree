require "test_helper"

# PAY-04: what a Checkout Session is made from (card only, the platform fee from the plan) and
# who can pay online.
class OnlinePaymentsTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @gateway = use_fake_payment_gateway
    @invoice = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Invoice.start(client:).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
        _1.tax_rates = []
        _1.save!
      end
    end
  end

  test "a session is a card payment on the invoice, with no platform fee unless the plan sets one" do
    params = as_business(@business) { OnlinePayments.checkout_session_params(@invoice, amount_cents: 12_345, success_url: "s", cancel_url: "c") }
    assert_equal [ "card" ], params[:payment_method_types]
    assert_equal [ 12_345, "usd" ], params[:line_items].first[:price_data].values_at(:unit_amount, :currency)
    assert_equal @invoice.uid, params[:metadata][:shadetree_invoice]
    assert_nil params[:payment_intent_data][:application_fee_amount]

    @business.plan.update!(platform_fee_bps: 50)
    params = as_business(@business) { OnlinePayments.checkout_session_params(@invoice.reload, amount_cents: 12_345, success_url: "s", cancel_url: "c") }
    assert_equal 61, params[:payment_intent_data][:application_fee_amount]
    assert_equal "61", params[:metadata][:shadetree_fee_cents]
  end

  test "only a sent invoice with a balance, of a business taking payments, for a client not erased, is payable online" do
    as_business(@business) do
      assert_not @invoice.online_payable?, "a draft"
      @invoice.mark_sent!(by: users(:one), channel: "link")
      assert_not @invoice.reload.online_payable?, "no payment account"
      account = PaymentAccount.create!(account_id: "acct_test1", details_submitted: true, charges_enabled: true, payouts_enabled: true)
      @business.reload
      assert @invoice.reload.online_payable?
      account.update!(charges_enabled: false)
      @business.reload
      assert_not @invoice.reload.online_payable?, "Stripe turned charges off"
      account.update!(charges_enabled: true)
      @business.reload
      @invoice.client.update_columns(erased_at: Time.current)
      assert_not @invoice.reload.online_payable?, "INS-02: an erased client"
    end
  end

  test "method details read well, and a Stripe failure leaves just the method" do
    account = as_business(@business) { PaymentAccount.create!(account_id: "acct_test1") }
    @gateway.payments["pi_1"] = { "brand" => "amex", "last4" => "0005" }
    assert_equal "American Express ending 0005", OnlinePayments.method_detail(account, "pi_1")
    @gateway.fail_next!
    assert_nil OnlinePayments.method_detail(account, "pi_1")
  end
end
