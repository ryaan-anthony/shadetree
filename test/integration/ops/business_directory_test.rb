require "test_helper"

# OPS-02: the business directory: search, filters, the business page and its audit entry.
class Ops::BusinessDirectoryTest < ActionDispatch::IntegrationTest
  setup { @one, @two = businesses(:one), businesses(:two) }

  test "non-operators, and operators who haven't entered a code, can't open the directory" do
    get ops_businesses_path
    assert_response :not_found, "signed out"
    sign_in users(:two)
    get ops_businesses_path
    assert_response :not_found
    get ops_business_path(@one)
    assert_response :not_found
    assert_not AuditEntry.exists?(action: "business.viewed")
  end

  test "operators search by name or any member's email, and filter by plan, status and signup" do
    sign_in_operator
    get ops_businesses_path
    assert_select "#businesses li", Business.count

    get ops_businesses_path(q: "business two")
    assert_select "#business-#{@two.uid}"
    assert_select "#business-#{@one.uid}", 0

    get ops_businesses_path(q: "USER1@example")
    assert_select "#business-#{@one.uid}"
    assert_select "#business-#{@two.uid}", 1, "user one is a technician in business two"

    get ops_businesses_path(q: "100%_")
    assert_select "#businesses", 0
    assert_match "No businesses match", response.body

    @two.update_columns(active: false, created_at: 40.days.ago)
    get ops_businesses_path(status: "closed")
    assert_select "#businesses li", 1
    assert_select "#business-#{@two.uid}"
    get ops_businesses_path(from: 10.days.ago.to_date.iso8601)
    assert_select "#business-#{@two.uid}", 0
    get ops_businesses_path(to: 30.days.ago.to_date.iso8601, from: "nonsense")
    assert_select "#businesses li", 1
    get ops_businesses_path(plan: plans(:free).id)
    assert_select "#business-#{@one.uid}"
  end

  test "sorts by last activity and paginates" do
    sign_in_operator
    business_users(:two).update_columns(last_active_at: 1.minute.ago)
    business_users(:one).update_columns(last_active_at: 2.days.ago)
    business_users(:one_member_of_two).update_columns(last_active_at: nil)
    get ops_businesses_path(sort: "activity")
    assert_equal [ @two.uid, @one.uid ], css_select("#businesses li").map { _1["id"].delete_prefix("business-") }.first(2)
    get ops_businesses_path(sort: "inactive", q: "test business")
    assert_equal [ @one.uid, @two.uid ], css_select("#businesses li").map { _1["id"].delete_prefix("business-") }

    stub_const_per_page(1) do
      get ops_businesses_path(page: 2, q: "test business")
      assert_select "#businesses li", 1
      assert_select ".pagination", /2–2/
    end
  end

  test "a business page shows members, plan, usage, counts and setup, and is audited" do
    sign_in_operator
    as_business(@one) { Client.create!(display_name: "Ana Secret-Client", contact_methods_attributes: [ { kind: "email", value: "ana@private.example" } ]) }
    assert_difference -> { AuditEntry.where(action: "business.viewed", business: @one).count } do
      get ops_business_path(@one)
    end
    assert_response :success
    assert_equal users(:one).email, AuditEntry.last.operator_email
    assert_select "#members li", @one.business_users.count
    assert_select "#member-#{business_users(:one).uid}", /Owner/
    assert_select "#former-members", 0
    assert_select "#usage-quotes_sent", /0 of/
    assert_select "#count-clients", /1/
    assert_select "#setup-progress", /of 4 steps/
    assert_select "#payments-account", /Not connected/
    account = as_business(@one) { PaymentAccount.create!(account_id: "acct_test1", details_submitted: true, disabled_reason: "requirements.past_due") }
    get ops_business_path(@one)
    assert_select "#payments-account", /Payments: Restricted.*acct_test1/m
    assert_select "#payments-restriction", /needs more information/
    get ops_businesses_path
    assert_select "#business-#{@one.uid}", /Payments: Restricted/
    as_business(@one) { account.update!(disconnected_at: Time.current, disconnected_reason: "provider") }
    get ops_business_path(@one)
    assert_select "#payments-account", /Disconnected .* \(in Stripe\)/
    assert_select "#billing-history li", 6
    assert_no_match "Ana Secret-Client", response.body, "no client personal data"
    assert_no_match "ana@private.example", response.body

    get ops_business_path("nope")
    assert_response :not_found
  end

  test "a business page shows the Stripe subscription and the billing history (BIL-04)" do
    customer = with_stripe_customer(@one)
    id = stripe.add_subscription(customer:, plan: plans(:starter), interval: "yearly")
    Billing::SubscriptionSync.refresh!(@one, id)
    as_business(@one) { BillingEvent.record!("payment_succeeded", details: { "amount_cents" => 19000, "currency" => "usd", "invoice" => "SHADE-1" }) }
    sign_in_operator

    get ops_business_path(@one)

    assert_select "#subscription-status", /Active · Starter, yearly\s+Renews/
    assert_select "#stripe-customer a[href='https://dashboard.stripe.com/test/customers/#{customer}']", customer
    assert_select "#billing-events li", 3
    assert_select "#billing-events", /Payment received: \$190\.00 · invoice SHADE-1/
    assert_select "#billing-events", /Plan changed: Free → Starter/
    assert_select "#billing-events", /Subscribed: Starter, yearly/
  end

  test "an operator who hasn't set up or entered a code is sent to do that first" do
    Operator.grant!(users(:one))
    sign_in users(:one)
    get ops_business_path(@one)
    assert_redirected_to ops_two_factor_setup_path
    assert_not AuditEntry.exists?(action: "business.viewed")
  end

  test "the console never prefetches pages on hover, since opening a business is audited" do
    sign_in_operator
    get ops_businesses_path
    assert_select "meta[name=turbo-prefetch][content=false]"
  end

  test "the list names an active owner and counts results; former members are tucked away" do
    sign_in_operator
    business_users(:one_member_of_two).update_columns(role: "owner")
    business_users(:two).update_columns(active: false, role: "technician")
    get ops_businesses_path(q: "business two")
    assert_select "#directory-count", "1 business match"
    assert_select "#business-#{@two.uid}", /user1@example.com/
    assert_select "#business-#{@two.uid}", text: /user2@example.com/, count: 0
    get ops_business_path(@two)
    assert_select "#former-members summary", "Former members (1)"
  end

  private

  def stub_const_per_page(value)
    original = Ops::BusinessesController::PER_PAGE
    Ops::BusinessesController.send(:remove_const, :PER_PAGE)
    Ops::BusinessesController.const_set(:PER_PAGE, value)
    yield
  ensure
    Ops::BusinessesController.send(:remove_const, :PER_PAGE)
    Ops::BusinessesController.const_set(:PER_PAGE, original)
  end
end
