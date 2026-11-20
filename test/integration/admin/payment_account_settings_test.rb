require "test_helper"

# PAY-03: Settings → Payments. Owners connect through Stripe's hosted onboarding, come back,
# resume, and disconnect; Admins only see the status; nobody sees another business's account.
class Admin::PaymentAccountSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @gateway = use_fake_payment_gateway
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def account = as_business(@business) { PaymentAccount.current }

  test "an owner connects, leaves part-way, resumes, finishes, and the status follows" do
    get admin_payment_account_path
    assert_response :success
    assert_select "#connect-stripe", /Set up payments with Stripe/
    policy = response.headers["Content-Security-Policy"]
    assert_match %r{form-action 'self' https://connect\.stripe\.com}, policy, "the form is redirected to Stripe"

    post admin_payment_account_path
    assert_response :see_other
    assert_equal "https://connect.stripe.com/setup/s/acct_test1/test", response.location
    _, account_id, urls = @gateway.calls_to(:onboarding_url).last
    assert_equal "acct_test1", account_id
    assert_equal return_admin_payment_account_url, urls[:return_url]
    assert_equal resume_admin_payment_account_url, urls[:refresh_url]
    assert_equal [ users(:one) ], [ account.connected_by ]

    get return_admin_payment_account_path
    assert_redirected_to admin_payment_account_path
    assert_match "Setup isn't finished", flash[:notice]
    follow_redirect!
    assert_select "#payment-status", /Setup not finished/
    assert_select "#continue-setup", /Continue setup/

    get resume_admin_payment_account_path
    assert_redirected_to "https://connect.stripe.com/setup/s/acct_test1/test"
    post admin_payment_account_path
    assert_equal 1, @gateway.calls_to(:create_account).size, "the same account is resumed, not a new one"

    @gateway.accounts["acct_test1"].merge!("details_submitted" => true, "charges_enabled" => true, "payouts_enabled" => true,
                                           "requirements" => { "currently_due" => [], "past_due" => [], "pending_verification" => [] })
    get return_admin_payment_account_path
    assert_match "set up to take card payments", flash[:notice]
    follow_redirect!
    assert_select "#payment-status", /Active/
    assert_select "#stripe-dashboard[href=?]", "https://dashboard.stripe.com/"
    assert_select "#continue-setup", false
  end

  test "a restricted account shows Stripe's reason and a way to fix it" do
    as_business(@business) do
      PaymentAccount.create!(account_id: "acct_test5", details_submitted: true, disabled_reason: "requirements.past_due",
                             requirements_due: [ "individual.id_number" ])
    end
    get admin_payment_account_path
    assert_select "#payment-status", /Restricted/
    assert_select "#restriction", /needs more information/
    assert_select "#continue-setup", /Update details in Stripe/
  end

  test "disconnecting ends access and hides the account; the owner can connect again" do
    as_business(@business) { PaymentAccount.create!(account_id: "acct_test7", details_submitted: true, charges_enabled: true, payouts_enabled: true) }
    delete admin_payment_account_path
    assert_redirected_to admin_payment_account_path
    assert_match "Stripe is disconnected", flash[:notice]
    assert_equal [ [ :disconnect, "acct_test7" ] ], @gateway.calls_to(:disconnect)
    assert_nil account
    follow_redirect!
    assert_select "#connect-stripe"
  end

  test "onboarding only ever redirects to Stripe" do
    @gateway.define_singleton_method(:onboarding_url) { |*, **| "https://evil.example/setup" }
    post admin_payment_account_path
    assert_redirected_to admin_payment_account_path
    assert_match "Stripe didn't respond", flash[:alert]
  end

  test "Stripe failing changes nothing and says so" do
    @gateway.fail_next!
    post admin_payment_account_path
    assert_redirected_to admin_payment_account_path
    assert_match "Stripe didn't respond", flash[:alert]
    assert_nil account
  end

  test "without Stripe keys the page says payments aren't available" do
    use_fake_payment_gateway(configured: false)
    get admin_payment_account_path
    assert_select "#payments-unavailable"
    assert_select "#connect-stripe", false
    post admin_payment_account_path
    assert_match "aren't available yet", flash[:alert]
  end

  test "only owners connect or disconnect; admins see the status; technicians nothing" do
    as_business(@business) { PaymentAccount.create!(account_id: "acct_test8") }
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_payment_account_path }
    assert_permission_matrix(owner: true, admin: false, technician: false) { get resume_admin_payment_account_path }
    assert_permission_matrix(owner: true, admin: false, technician: false) { get return_admin_payment_account_path }
    admin = member_with_role(:admin)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_payment_account_path
    assert_select "#continue-setup", false
    assert_select "#disconnect", false
    delete admin_payment_account_path
    assert_response :forbidden
    post admin_payment_account_path
    assert_response :forbidden
    assert_empty @gateway.calls_to(:disconnect)
  end

  test "another business's account is never shown or touched" do
    as_business(businesses(:two)) { PaymentAccount.create!(account_id: "acct_other") }
    get admin_payment_account_path
    assert_select "#connect-stripe"
    delete admin_payment_account_path
    assert_redirected_to admin_payment_account_path
    assert_empty @gateway.calls_to(:disconnect)
    as_business(businesses(:two)) { assert PaymentAccount.current.connected? }
  end
end
