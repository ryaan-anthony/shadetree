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

  def ours(extra = {}) = { "metadata" => { "shadetree_business" => @business.uid, "shadetree_invoice" => @invoice.uid } }.merge(extra)

  test "paying more than is owed records it and asks the team to refund the difference; a void invoice stays void" do
    deliver("payment_intent.succeeded", { id: "pi_a", object: "payment_intent", amount_received: 15_000, currency: "usd", metadata: })
    deliver("payment_intent.succeeded", { id: "pi_b", object: "payment_intent", amount_received: 15_000, currency: "usd", metadata: })
    assert_equal [ "paid", 30_000 ], [ invoice.status, invoice.amount_paid_cents ]
    as_business(@business) do
      notice = Notification.where(kind: "payment_attention").sole
      assert_equal [ "Invoice #{@invoice.number} was overpaid by $100.00", @invoice ], [ notice.title, notice.subject ]
      assert_match "Refund $100.00", notice.body
    end

    other = as_business(@business) do
      Invoice.start(client: @invoice.client).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "X", "quantity" => "1", "unit_price" => "40", "taxable" => "0" } ])
        _1.tax_rates = []
        _1.save!
        _1.mark_sent!(by: users(:one), channel: "link")
        _1.void!(reason: "Duplicate", by: users(:one))
      end
    end
    deliver("payment_intent.succeeded", { id: "pi_c", object: "payment_intent", amount_received: 4_000, currency: "usd", metadata: metadata(other) })
    as_business(@business) do
      assert_equal [ "void", 4_000 ], [ other.reload.status, other.amount_paid_cents ], "void, with the money it took counted"
      assert Notification.where(kind: "payment_attention", subject: other).where("title LIKE ?", "%after it was voided%").exists?
    end
  end

  test "a full refund or a lost dispute that reopens the invoice isn't chased by overdue automations, and the team is told" do
    rule = as_business(@business) { AutomationRule.create!(name: "Chase", trigger: "invoice_overdue", actions: [ { "type" => "notify_team", "team" => "office" } ]) }
    deliver("checkout.session.completed", session)
    deliver("charge.refunded", { id: "ch_1", object: "charge", payment_intent: "pi_1", amount: 20_000, amount_refunded: 20_000, currency: "usd" })
    assert_equal [ "sent", 0, "Refunded" ], [ invoice.status, invoice.amount_paid_cents, payments.first.adjustment_label ]
    as_business(@business) do
      run = AutomationRun.find_by!(rule:, subject: @invoice)
      assert_equal "skipped", run.status
      assert_match "Reopened after a refund", run.log.first["detail"]
      notice = Notification.where(kind: "payment_attention").sole
      assert_match "awaiting payment again after a refund", notice.title
      @invoice.update_columns(issued_on: @business.today - 10, due_on: @business.today - 3)
      assert_not Automation.overdue_without_run(rule, @business).exists?(@invoice.id), "the overdue sweep won't pick it up"
    end

    second = as_business(@business) do
      Invoice.start(client: @invoice.client).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "X", "quantity" => "1", "unit_price" => "40", "taxable" => "0" } ])
        _1.tax_rates = []
        _1.save!
        _1.mark_sent!(by: users(:one), channel: "link")
      end
    end
    deliver("checkout.session.completed", session(amount: 4_000, intent: "pi_2").merge(metadata: metadata(second)))
    deliver("charge.dispute.created", { id: "dp_2", object: "dispute", payment_intent: "pi_2", amount: 4_000, status: "needs_response" })
    deliver("charge.dispute.closed", { id: "dp_2", object: "dispute", payment_intent: "pi_2", amount: 4_000, status: "lost" })
    as_business(@business) do
      assert_equal "sent", second.reload.status
      assert Notification.where(kind: "payment_attention", subject: second).where("title LIKE ?", "%lost dispute%").exists?, "a lost dispute tells the team too"
      assert AutomationRun.exists?(rule:, subject: second, status: "skipped")
    end
  end

  test "a refund that arrives before its payment is retried until the payment is in; others' charges are ignored" do
    @gateway.payments["pi_1"] = ours("brand" => "visa", "last4" => "4242", "amount_refunded" => 5_000, "created" => 2.days.ago.to_i)
    payload, signature = signed_connect_event("charge.refunded", { id: "ch_1", object: "charge", payment_intent: "pi_1", amount_refunded: 5_000 }, id: "evt_early")
    perform_enqueued_jobs(only: ProcessConnectEventJob) do
      post stripe_connect_webhook_path, params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => signature }
    end
    early = ConnectEvent.find_by!(event_id: "evt_early")
    assert_equal "failed", early.status
    assert_match "isn't recorded yet", early.error

    deliver("checkout.session.completed", session)
    payment = payments.sole
    assert_equal 5_000, payment.refunded_cents, "what Stripe already knew came with the payment"
    assert_equal @business.today - 2, payment.received_on, "the day the card was charged"
    early.update_columns(updated_at: 11.minutes.ago)
    RetryConnectEventsJob.perform_now
    assert_equal "processed", early.reload.status

    deliver("charge.refunded", { id: "ch_9", object: "charge", payment_intent: "pi_someone_elses", amount_refunded: 100 }, id: "evt_other")
    assert_equal "processed", ConnectEvent.find_by!(event_id: "evt_other").status
  end

  test "an inquiry that closes isn't a won dispute" do
    deliver("checkout.session.completed", session)
    deliver("charge.dispute.closed", { id: "dp_1", object: "dispute", payment_intent: "pi_1", amount: 20_000, status: "warning_closed" })
    assert_equal [ "closed", "Inquiry closed" ], [ payments.first.dispute_status, payments.first.adjustment_label ]
    assert_equal "paid", invoice.status
  end

  test "totals leave out refunds; the receipt waits for the hourly cap; erasing the client removes the card details" do
    deliver("checkout.session.completed", session)
    deliver("charge.refunded", { id: "ch_1", object: "charge", payment_intent: "pi_1", amount_refunded: 5_000 })
    as_business(@business) do
      assert_equal 15_000, Payment.where(invoice: @invoice).counted_sum
      assert_equal [ Money.new(15_000, "USD") ], ActionDashboard.new(@business).payments_this_month
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_client_path(@invoice.client)
    assert_select "#client-lifetime-paid", /\$150\.00/

    as_business(@business) do
      EmailMessage::CLIENT_EMAILS_PER_HOUR.times { EmailMessage.create!(kind: "payment_receipt", to: "someone@example.com") }
      assert_enqueued_with(job: OnlineReceiptJob) { OnlinePayments.send_receipt(payments.first) }
      EmailMessage.where(to: "someone@example.com").update_all(created_at: 2.hours.ago)
      assert_difference -> { EmailMessage.where(kind: "payment_receipt", to: "maria@example.com").count }, 0 do
        OnlineReceiptJob.perform_now(payments.first.id) # it already had one
      end
    end

    as_business(@business) { ClientErasure.new(@invoice.client, by: users(:one)).erase! }
    as_business(@business) do
      assert_nil payments.first.method_detail
      assert_empty @invoice.events.reload.select { _1.data.key?("detail") }
      assert Notification.where(subject: @invoice).all? { _1.title.exclude?("Maria") }, "notifications about the invoice are scrubbed"
    end
  end
end
