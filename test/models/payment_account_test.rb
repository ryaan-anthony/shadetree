require "test_helper"

# PAY-03: the payment account's status, as Stripe reports it, and disconnecting.
class PaymentAccountTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @gateway = use_fake_payment_gateway
    @account = as_business(@business) { PaymentAccount.create!(account_id: "acct_test1") }
  end

  def stripe_account(details: true, charges: true, payouts: true, due: [], past_due: [], pending: [], disabled: nil, deadline: nil)
    { "id" => "acct_test1", "country" => "US", "details_submitted" => details, "charges_enabled" => charges, "payouts_enabled" => payouts,
      "requirements" => { "currently_due" => due, "past_due" => past_due, "pending_verification" => pending, "disabled_reason" => disabled,
                          "current_deadline" => deadline } }
  end

  test "status follows what Stripe says, through every state" do
    as_business(@business) do
      assert_equal "onboarding_incomplete", @account.status
      assert_not @account.accepts_payments?

      @account.sync!(stripe_account(charges: false, payouts: false, pending: [ "individual.verification.document" ], disabled: "requirements.pending_verification"))
      assert_equal [ "pending_verification", "Pending verification" ], [ @account.status, @account.status_label ]

      @account.sync!(stripe_account)
      assert_equal "active", @account.status
      assert @account.accepts_payments?
      assert_not @account.fixable_in_onboarding?

      @account.sync!(stripe_account(due: [ "individual.id_number" ], deadline: Time.zone.parse("2026-12-15 12:00").to_i))
      assert_equal "restricted", @account.status
      assert @account.accepts_payments?, "charges still work until the deadline"
      assert_match "by December 15, 2026", @account.restriction_reason

      @account.sync!(stripe_account(charges: false, payouts: false, past_due: [ "individual.id_number" ], disabled: "requirements.past_due"))
      assert_equal "restricted", @account.status
      assert_match "before it can turn payments back on", @account.restriction_reason
      assert @account.fixable_in_onboarding?

      @account.sync!(stripe_account(charges: false, payouts: false, disabled: "rejected.fraud"))
      assert_match "closed this account", @account.restriction_reason
      assert_not @account.fixable_in_onboarding?
    end
  end

  test "disconnecting ends our access at Stripe, unless Stripe told us; the business sees no account after" do
    as_business(@business) do
      @account.sync!(stripe_account)
      assert @business.reload.accepts_online_payments?
      @account.disconnect!(reason: "owner", by: users(:one))
      assert_equal [ [ :disconnect, "acct_test1" ] ], @gateway.calls_to(:disconnect)
      assert_not @account.reload.connected?
      assert_equal "owner", @account.disconnected_reason
      assert_nil @business.reload.payment_account
      assert_not @business.accepts_online_payments?

      other = PaymentAccount.create!(account_id: "acct_test2")
      other.disconnect!(reason: "provider")
      assert_equal 1, @gateway.calls_to(:disconnect).size, "Stripe already ended it"
    end
  end

  test "one connected account per business, and events find theirs across businesses" do
    as_business(@business) { assert_raises(ActiveRecord::RecordNotUnique) { PaymentAccount.create!(account_id: "acct_test9") } }
    assert_equal @account, PaymentAccount.for_account("acct_test1")
    assert_nil PaymentAccount.for_account("acct_unknown")
    as_business(businesses(:two)) { assert_raises(ActiveRecord::RecordNotFound) { PaymentAccount.find_by_param!(@account.uid) } }
  end

  test "disconnecting at Stripe: only 'not connected' counts as already done" do
    not_connected = Stripe::OAuth::InvalidClientError.new("invalid_client", "This application is not connected to stripe account acct_1, or that account does not exist.")
    wrong_client = Stripe::OAuth::InvalidClientError.new("invalid_client", "No such application: 'ca_wrong'")
    assert PaymentGateway.already_disconnected?(not_connected)
    assert_not PaymentGateway.already_disconnected?(wrong_client)
    assert_not PaymentGateway.already_disconnected?(Stripe::OAuth::InvalidRequestError.new("invalid_request", "not connected to"))
  end

  test "live mode follows the secret key" do
    previous = Stripe.api_key
    Stripe.api_key = "sk_live_x"
    assert PaymentGateway.live_mode?
    Stripe.api_key = "rk_live_x"
    assert PaymentGateway.live_mode?
    Stripe.api_key = "sk_test_x"
    assert_not PaymentGateway.live_mode?
  ensure
    Stripe.api_key = previous
  end
end
