require "test_helper"

# BIL-04: Owners choose a plan on Stripe Checkout, switch or cancel in the customer portal, and
# come back with the new plan active. Admins see the plan, not the billing actions.
class Admin::BillingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    Billing::PlanSync.new.run!
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def subscribe(plan = plans(:starter), interval: "monthly")
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan:, interval:)
    Billing::SubscriptionSync.refresh!(@business, id)
    id
  end

  test "an Owner chooses a plan and interval and is sent to Stripe Checkout, as a new customer named for the business" do
    get admin_plan_path
    assert_select "#choose-starter form[action='#{admin_billing_checkout_path}'][data-turbo=false]", 2
    assert_select "#choose-free", /Your plan/
    assert_match "form-action 'self' https://checkout.stripe.com https://billing.stripe.com", response.headers["Content-Security-Policy"]

    post admin_billing_checkout_path, params: { plan: "starter", interval: "yearly" }

    session = stripe.checkout_sessions.values.sole
    assert_redirected_to session[:url]
    assert_equal 303, response.status
    customer = stripe.customers.values.sole
    assert_equal({ business_uid: @business.uid }, customer[:metadata])
    assert_equal [ @business.name, nil ], customer.values_at(:name, :email), "no personal details are sent"
    assert_equal customer[:id], @business.reload.stripe_customer_id
    yearly = stripe.prices.find { _1[:lookup_key] == "shadetree_starter_yearly" }
    assert_equal [ { price: yearly[:id], quantity: 1 } ], session[:line_items]
    assert_equal [ "subscription", customer[:id], @business.uid, { enabled: true } ], session.values_at(:mode, :customer, :client_reference_id, :automatic_tax)
    assert_equal "#{admin_billing_done_url}?session_id={CHECKOUT_SESSION_ID}", session[:success_url]
    assert_equal admin_plan_url, session[:cancel_url]

    post admin_billing_checkout_path, params: { plan: "business", interval: "monthly" }
    assert_equal 1, stripe.customers.size, "one customer per business"
  end

  test "subscribing during a trial keeps the rest of it when 48 hours or more are left (BIL-05)" do
    @business.update_columns(trial_plan_id: plans(:business).id, trial_ends_at: 5.days.from_now, billing_status: "trialing")
    post admin_billing_checkout_path, params: { plan: "starter", interval: "monthly" }
    assert_equal @business.trial_ends_at.to_i, stripe.checkout_sessions.values.last[:subscription_data][:trial_end]

    @business.update_columns(trial_ends_at: 47.hours.from_now)
    post admin_billing_checkout_path, params: { plan: "starter", interval: "monthly" }
    assert_nil stripe.checkout_sessions.values.last[:subscription_data][:trial_end]
  end

  test "back from Checkout, the new plan is active at once" do
    post admin_billing_checkout_path, params: { plan: "starter", interval: "monthly" }
    session = stripe.checkout_sessions.values.sole
    id = stripe.add_subscription(customer: session[:customer], plan: plans(:starter))
    session.merge!(status: "complete", subscription: id)

    get admin_billing_done_path(session_id: session[:id])

    assert_redirected_to admin_plan_path
    assert_equal "Thanks! You're on Starter now.", flash[:notice]
    assert_equal plans(:starter), @business.reload.plan
    follow_redirect!
    assert_select "#current-plan", /You're on Starter/
    assert_select "#billing", /\$19\.00 a month, billed monthly\. Renews on/
    assert_select "#billing form[action='#{admin_billing_portal_path}']", 1
  end

  test "a session that isn't finished or isn't this business's changes nothing" do
    with_stripe_customer(@business)
    other = stripe.create_checkout_session(customer: "cus_other", status: "complete")
    stripe.checkout_sessions[other.id][:status] = "complete"
    stripe.checkout_sessions[other.id][:subscription] = stripe.add_subscription(customer: "cus_other", plan: plans(:business))

    get admin_billing_done_path(session_id: other.id)
    get admin_billing_done_path(session_id: "nonsense")

    assert_match "being confirmed", flash[:notice]
    assert_equal plans(:free), @business.reload.plan
  end

  test "with a subscription, choosing another plan or interval confirms the switch in the portal, and Free cancels there" do
    id = subscribe
    get admin_plan_path
    assert_select "#choose-starter", /Your plan/
    assert_select "#choose-starter form", 1, "the other interval"
    assert_select "#choose-business form", /Switch to Business/

    post admin_billing_checkout_path, params: { plan: "business", interval: "yearly" }

    portal = stripe.portal_sessions.last
    assert_redirected_to portal[:url]
    confirm = portal[:flow_data][:subscription_update_confirm]
    assert_equal id, confirm[:subscription]
    assert_equal [ { id: "si_#{id}", price: stripe.prices.find { _1[:lookup_key] == "shadetree_business_yearly" }[:id], quantity: 1 } ], confirm[:items]
    assert_equal stripe.portal_configurations.sole.id, portal[:configuration]
    assert_empty stripe.checkout_sessions

    post admin_billing_checkout_path, params: { plan: "free", interval: "monthly" }
    assert_equal({ type: "subscription_cancel", subscription_cancel: { subscription: id },
                   after_completion: { type: "redirect", redirect: { return_url: admin_plan_url } } }, stripe.portal_sessions.last[:flow_data])
  end

  test "Manage billing opens the customer portal; a cancelled plan says when it ends" do
    id = subscribe
    stripe.subscriptions[id][:cancel_at_period_end] = true
    Billing::SubscriptionSync.refresh!(@business, id)
    get admin_plan_path
    assert_select "#billing", /Cancelled: your plan runs until .*then you're on Free/

    post admin_billing_portal_path
    assert_redirected_to stripe.portal_sessions.last[:url]
    assert_equal [ @business.stripe_customer_id, admin_plan_url ], stripe.portal_sessions.last.values_at(:customer, :return_url)
    post admin_billing_portal_path, params: { flow: "payment" }
    assert_equal "payment_method_update", stripe.portal_sessions.last[:flow_data][:type]
  end

  test "Admins see the plan but not billing actions; only Owners can use them" do
    admin = member_with_role(:admin, business: @business)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_plan_path
    assert_response :success
    assert_select "#choose-plan", 0
    assert_select "#billing", /Only .* can change the plan or billing/
    sign_out admin

    assert_permission_matrix(owner: true, admin: false, technician: false) { post admin_billing_portal_path }
    assert_permission_matrix(owner: true, admin: false, technician: false) { post admin_billing_checkout_path, params: { plan: "starter" } }
    assert_permission_matrix(owner: true, admin: false, technician: false) { get admin_billing_done_path }
  end

  test "a new Owner takes over the same billing" do
    subscribe
    successor = users(:two)
    @business.business_users.create!(user: successor, role: "owner", active: true)
    @business.business_users.find_by(user: users(:one)).update!(role: "admin")
    sign_in successor
    post switch_admin_business_path, params: { business: @business.uid }

    post admin_billing_portal_path

    assert_equal @business.stripe_customer_id, stripe.portal_sessions.last[:customer]
    assert_empty stripe.customers, "no new customer"
  end

  test "when Stripe isn't reachable or set up, the Owner is told plainly" do
    stripe.fail_with = Stripe::APIConnectionError.new("down")
    post admin_billing_checkout_path, params: { plan: "starter", interval: "monthly" }
    assert_redirected_to admin_plan_path
    assert_match "Billing isn't available right now", flash[:alert]

    stripe.fail_with = nil
    stripe.prices.clear
    post admin_billing_checkout_path, params: { plan: "starter", interval: "monthly" }
    assert_match "Billing isn't available right now", flash[:alert]
  end

  test "an unknown plan, Free with nothing to cancel, a hidden plan or an unknown interval isn't available" do
    plans(:business).update!(public: false)
    [ { plan: "nope", interval: "monthly" }, { plan: "free", interval: "monthly" }, { plan: "starter", interval: "weekly" },
      { plan: "starter" }, { plan: "business", interval: "monthly" } ].each do |params|
      post admin_billing_checkout_path, params: params
      assert_redirected_to admin_plan_path
      assert_equal "That plan isn't available.", flash[:alert], params.inspect
    end
    plans(:starter).update!(annual_price_cents: 0)
    post admin_billing_checkout_path, params: { plan: "starter", interval: "yearly" }
    assert_equal "That plan isn't available.", flash[:alert]
    assert_empty stripe.checkout_sessions
  end

  test "a live subscription Stripe has that hasn't reached us yet sends the Owner to the portal, not a second Checkout" do
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter))

    post admin_billing_checkout_path, params: { plan: "business", interval: "monthly" }

    assert_empty stripe.checkout_sessions
    assert_equal id, stripe.portal_sessions.last[:flow_data][:subscription_update_confirm][:subscription]
    assert_equal plans(:starter), @business.reload.plan
  end

  test "back from Checkout, a failed lookup says the payment is being confirmed, never to pay again" do
    with_stripe_customer(@business)
    stripe.fail_with = Stripe::APIConnectionError.new("down")
    get admin_billing_done_path(session_id: "cs_test1")
    assert_redirected_to admin_plan_path
    assert_equal "Your payment is being confirmed. Your plan will update in a minute or two.", flash[:notice]
    assert_nil flash[:alert]
  end

  test "Stripe's return links use APP_HOST when it's set" do
    ENV["APP_HOST"] = "app.getshadetree.com"
    post admin_billing_checkout_path, params: { plan: "starter", interval: "monthly" }
    session = stripe.checkout_sessions.values.sole
    assert_equal [ "https://app.getshadetree.com/admin/plan/billing/done?session_id={CHECKOUT_SESSION_ID}", "https://app.getshadetree.com/admin/plan" ],
                 session.values_at(:success_url, :cancel_url)
  ensure
    ENV.delete("APP_HOST")
  end

  test "a suspended business's Owner can see the plan and open the portal, nothing else; others can't" do
    subscribe
    @business.suspend!(reason: "spam")
    get admin_plan_path
    assert_response :success
    assert_select "#choose-plan", 0
    post admin_billing_portal_path
    assert_redirected_to stripe.portal_sessions.last[:url]
    post admin_billing_checkout_path, params: { plan: "business", interval: "monthly" }
    assert_response :forbidden
    get admin_root_path
    assert_select "#business-suspended a[href='#{admin_plan_path}']"

    admin = member_with_role(:admin, business: @business)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_plan_path
    assert_response :forbidden
  end
end

# BIL-05: what Owners see of a trial and a failing renewal.
class Admin::BillingLifecycleTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "a trial shows its days left on the plan page, and a banner in its last days" do
    @business.update_columns(trial_plan_id: plans(:business).id, trial_ends_at: 5.days.from_now)
    Billing::PlanResolver.apply!(@business)
    get admin_plan_path
    assert_select "#trial-status", /Business trial: 5 days left/
    assert_select "#billing-banner", 0
    @business.update_columns(trial_ends_at: 2.days.from_now)
    get admin_root_path
    assert_select "#billing-banner", /Business trial ends on/
    @business.update_columns(trial_ends_at: 3.days.from_now)
    get admin_plan_path
    assert_select "#trial-status", /first payment is on/
    assert_select "#billing", { text: /isn't billed through Shadetree/, count: 0 }
    @business.update_columns(trial_ends_at: 47.hours.from_now)
    get admin_plan_path
    assert_select "#trial-status", /the trial ends and billing starts straight away/
  end

  test "a failing renewal shows a banner on every page for Owners, with a way to update the card" do
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter), status: "past_due")
    Billing::SubscriptionSync.refresh!(@business, id)
    get admin_root_path
    assert_select "#billing-banner a[href='#{admin_plan_path(anchor: "billing")}']", /Update payment/
    get admin_plan_path
    assert_select "#past-due", /update your card by/
    assert_select "#billing form[action='#{admin_billing_portal_path}'] input[name=flow][value=payment]"

    admin = member_with_role(:admin, business: @business)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_select "#billing-banner", 0, "Owners only"
  end

  test "after the grace period the banner says the plan is on Free until a payment goes through" do
    customer = with_stripe_customer(@business)
    id = stripe.add_subscription(customer:, plan: plans(:starter), status: "past_due")
    Billing::SubscriptionSync.refresh!(@business, id)
    travel 8.days do
      BillingChecksJob.perform_now
      get admin_root_path
      assert_select "#billing-banner", /renewal wasn't paid, so you're on Free/
      assert_select "#billing-banner", { text: /to keep your plan/, count: 0 }
    end
  end
end
