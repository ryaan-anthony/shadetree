require "test_helper"

# PAY-04: payments, refunds and disputes are recorded from Stripe's Connect notifications only,
# once each, with the client's receipt, the team's notification and the payment_received
# automation trigger.
class Webhooks::OnlinePaymentsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @previous_secret = ENV["STRIPE_CONNECT_WEBHOOK_SECRET"]
    ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = "whsec_test"
    @gateway = use_fake_payment_gateway
    @business = businesses(:one)
    @business.update!(plan_overrides: { "features" => { "automations" => true } })
    @invoice = as_business(@business) do
      PaymentAccount.create!(account_id: "acct_test1", details_submitted: true, charges_enabled: true, payouts_enabled: true)
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      invoice = Invoice.start(client: maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
      invoice.tax_rates = []
      invoice.save!
      invoice.mark_sent!(by: users(:one), channel: "link")
      invoice
    end
  end

  teardown { ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = @previous_secret }

  def deliver(type, object, id: "evt_#{SecureRandom.hex(6)}")
    payload, signature = signed_connect_event(type, object, id:)
    perform_enqueued_jobs(only: ProcessConnectEventJob) do
      post stripe_connect_webhook_path, params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => signature }
    end
    assert_response :ok
  end

  def metadata(invoice = @invoice) = { shadetree_invoice: invoice.uid, shadetree_business: @business.uid, shadetree_fee_cents: "0" }

  def session(amount: 20_000, intent: "pi_1", status: "paid")
    { id: "cs_1", object: "checkout.session", payment_status: status, status: "complete", amount_total: amount, currency: "usd",
      payment_intent: intent, metadata:, customer_details: { email: "maria@example.com", name: "Maria Lopez" } }
  end

  def payments = as_business(@business) { @invoice.payments.reload.to_a }
  def invoice = as_business(@business) { @invoice.reload }

  test "a paid Checkout Session records the payment once, marks the invoice paid, emails a receipt and tells the team" do
    rule = as_business(@business) { AutomationRule.create!(name: "Thanks", trigger: "payment_received", actions: [ { "type" => "notify_team", "team" => "office" } ]) }
    @gateway.payments["pi_1"] = { "charge_id" => "ch_1", "brand" => "visa", "last4" => "4242", "wallet" => "apple_pay" }
    deliver("checkout.session.completed", session, id: "evt_a")

    assert_equal 1, payments.size
    payment = payments.first
    assert_equal [ "online", "card", 20_000, "pi_1", "cs_1", "Visa ending 4242 (Apple Pay)" ],
                 [ payment.source, payment.payment_method, payment.amount_cents, payment.reference, payment.provider_checkout_id, payment.method_detail ]
    assert_equal [ "paid", 20_000 ], [ invoice.status, invoice.amount_paid_cents ]
    as_business(@business) do
      assert_equal "Paid online", InvoicesHelper::EVENT_LABELS.fetch(@invoice.events.where(kind: "payment_received").sole.kind)
      assert_equal "client", ClientEvent.where(kind: "payment_recorded").sole.data["via"]
      assert_equal 1, AutomationRun.where(rule:).count, "NTF-04's payment_received trigger"
      assert_equal 1, Notification.where(kind: "online_payment").count
      assert_match "Maria Lopez paid $200.00 online", Notification.where(kind: "online_payment").first.title
      assert_equal [ "maria@example.com" ], EmailMessage.where(kind: "payment_receipt").pluck(:to)
    end
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.find { _1.to == [ "maria@example.com" ] && _1.subject.start_with?("Receipt") }
    assert_includes mail.text_part.body.to_s, "Visa ending 4242 (Apple Pay)"
    assert_includes mail.text_part.body.to_s, "Paid in full"

    # Stripe repeats itself: the same event, and the PaymentIntent's own event.
    deliver("checkout.session.completed", session, id: "evt_a")
    deliver("payment_intent.succeeded", { id: "pi_1", object: "payment_intent", status: "succeeded", amount_received: 20_000, currency: "usd", metadata: })
    assert_equal 1, payments.size, "never double-recorded"
    as_business(@business) { assert_equal 1, EmailMessage.where(kind: "payment_receipt").count }
  end

  test "a part payment leaves the invoice partly paid; the PaymentIntent event alone is enough" do
    deliver("payment_intent.succeeded", { id: "pi_2", object: "payment_intent", status: "succeeded", amount_received: 5_000, currency: "usd", metadata: })
    assert_equal [ "partially_paid", 15_000 ], [ invoice.status, invoice.balance.cents ]
  end

  test "unpaid sessions, other businesses' invoices and the wrong currency record nothing" do
    deliver("checkout.session.completed", session(status: "unpaid"))
    other = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Not yours", contact_methods_attributes: [ { kind: "phone", value: "555-0101" } ])
      Invoice.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "X", "quantity" => "1", "unit_price" => "10" } ]); _1.save! }
    end
    deliver("checkout.session.completed", session(intent: "pi_x").merge(metadata: metadata(other)))
    deliver("checkout.session.completed", session(intent: "pi_y").merge(metadata: metadata.merge(shadetree_business: businesses(:two).uid)))
    deliver("checkout.session.completed", session(intent: "pi_z").merge(currency: "eur"))
    assert_empty payments
    assert_equal 0, Tenancy.across_businesses(reason: "test") { Payment.count }
  end

  test "refunds and disputes Stripe reports are reflected on the payment and the invoice" do
    deliver("checkout.session.completed", session)
    deliver("charge.refunded", { id: "ch_1", object: "charge", payment_intent: "pi_1", amount: 20_000, amount_refunded: 5_000, refunded: false, currency: "usd" })
    payment = payments.first
    assert_equal [ 5_000, "Partly refunded" ], [ payment.refunded_cents, payment.adjustment_label ]
    assert_equal [ "partially_paid", 15_000 ], [ invoice.status, invoice.amount_paid_cents ]
    deliver("charge.refunded", { id: "ch_1", object: "charge", payment_intent: "pi_1", amount_refunded: 5_000 })
    as_business(@business) { assert_equal 1, @invoice.events.where(kind: "payment_refunded").count, "a repeat changes nothing" }

    deliver("charge.dispute.created", { id: "dp_1", object: "dispute", charge: "ch_1", payment_intent: "pi_1", amount: 15_000, status: "needs_response", reason: "fraudulent" })
    assert_equal "Disputed", payments.first.adjustment_label
    as_business(@business) { assert_equal 1, Notification.where(kind: "payment_disputed").count }
    deliver("charge.dispute.closed", { id: "dp_1", object: "dispute", payment_intent: "pi_1", amount: 15_000, status: "lost" })
    assert_equal [ "sent", 0 ], [ invoice.status, invoice.amount_paid_cents ]
    assert_equal "Dispute lost", payments.first.adjustment_label
  end

  test "money taken while the invoice changed is still recorded; a suspended business's payments still settle" do
    as_business(@business) { @invoice.revise!(by: users(:one)) }
    @business.suspend!(reason: "testing")
    deliver("checkout.session.completed", session)
    assert_equal [ "paid", 1 ], [ invoice.status, invoice.revision ], "the revision being prepared was dropped"
    assert_equal 1, payments.size
  end
end
