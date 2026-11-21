# PAY-04: clients paying invoices online, through Stripe Checkout on the business's own Stripe
# account (a direct charge; ADR 0024). Starting a payment (checkout_session_params) and acting on
# what Stripe confirms afterwards (record!, refund!, dispute!), called by ConnectEventHandler as
# the business. The browser's return is never taken as proof.
module OnlinePayments
  module_function

  # The smallest part payment a client may choose (when the business allows them), and the
  # least a part payment may leave owing (so nothing under Stripe's 50¢ is left to pay).
  MINIMUM_PART = 100 # cents

  BRANDS = { "amex" => "American Express", "diners" => "Diners Club", "jcb" => "JCB", "unionpay" => "UnionPay", "mastercard" => "Mastercard" }.freeze
  WALLETS = { "apple_pay" => "Apple Pay", "google_pay" => "Google Pay", "link" => "Link", "samsung_pay" => "Samsung Pay" }.freeze

  # The platform's cut on a payment, from the business's plan (0 unless one is ever set).
  def platform_fee_cents(business, amount_cents) = amount_cents * business.plan.platform_fee_bps.to_i / 10_000

  # What a Checkout Session for paying `amount_cents` of an invoice is made from. Card only
  # (Apple Pay and Google Pay come with it); delayed methods like ACH aren't offered.
  def checkout_session_params(invoice, amount_cents:, success_url:, cancel_url:)
    fee = platform_fee_cents(invoice.business, amount_cents)
    metadata = { shadetree_invoice: invoice.uid, shadetree_business: invoice.business.uid, shadetree_fee_cents: fee.to_s }
    name = "Invoice #{invoice.number}"
    { mode: "payment", payment_method_types: [ "card" ], client_reference_id: invoice.uid, metadata:,
      line_items: [ { quantity: 1, price_data: { currency: invoice.currency.downcase, unit_amount: amount_cents, product_data: { name: } } } ],
      payment_intent_data: { description: "#{name} (#{invoice.business.name})", metadata:, application_fee_amount: (fee if fee.positive?) }.compact,
      success_url:, cancel_url:, expires_at: CHECKOUT_LIFETIME.from_now.to_i }
  end

  CHECKOUT_LIFETIME = 1.hour

  # The client already paid through the Checkout page that's open (it's completing now).
  class CheckoutInProgress < StandardError; end

  # The Checkout page to send the client to for `amount_cents`: the one already open for that
  # amount (another tab, a double tap), or a new one, after closing any other first. One
  # payment, never two.
  def open_checkout!(invoice, amount_cents:, success_url:, cancel_url:)
    account = invoice.business.payment_account
    gateway = PaymentGateway.current
    invoice.with_lock do
      if invoice.open_checkout?
        next invoice.checkout_session_url if invoice.checkout_amount_cents == amount_cents
        raise CheckoutInProgress if gateway.expire_checkout_session(account.account_id, invoice.checkout_session_id) == "complete"
      end
      expires_at = CHECKOUT_LIFETIME.from_now
      params = checkout_session_params(invoice, amount_cents:, success_url:, cancel_url:).merge(expires_at: expires_at.to_i)
      session = gateway.create_checkout_session(account.account_id, params)
      invoice.remember_checkout!(session, amount_cents:, expires_at:)
      session.fetch("url")
    end
  end

  # A refund or dispute for one of our payments arrived before the payment itself: raised so the
  # event is tried again (ConnectEvent) once the payment is in.
  class PaymentNotRecordedYet < StandardError; end

  # Stripe's dispute statuses, as the payment keeps them.
  def dispute_status(stripe_status)
    case stripe_status.to_s
    when "won" then "won"
    when "lost" then "lost"
    when "warning_closed" then "closed"
    when "prevented" then "prevented"
    else "open"
    end
  end

  # A confirmed payment (a Checkout Session paid, or its PaymentIntent succeeded). Returns the
  # Payment, or nil when it isn't for an invoice of this account's business.
  def record!(account, intent_id:, amount_cents:, currency:, metadata:, checkout_id: nil)
    metadata ||= {}
    return if intent_id.blank? || amount_cents.to_i <= 0 || metadata["shadetree_business"] != account.business.uid

    invoice = Invoice.find_by(uid: metadata["shadetree_invoice"].to_s)
    return unless invoice && invoice.currency == currency.to_s.upcase
    return Payment.find_by(provider_payment_id: intent_id) if Payment.exists?(provider_payment_id: intent_id)

    charge = charge_details(account, intent_id)
    received_on = charge["created"] ? Time.zone.at(charge["created"].to_i).in_time_zone(account.business.time_zone).to_date : account.business.today
    payment, created, overpaid = invoice.record_online_payment!(
      intent_id:, amount_cents: amount_cents.to_i, currency:, checkout_id:, received_on: [ received_on, account.business.today ].min,
      method_detail: method_detail(charge), platform_fee_cents: metadata["shadetree_fee_cents"].to_i,
      refunded_cents: charge["amount_refunded"].to_i,
      dispute: charge["dispute"] && { "status" => dispute_status(charge.dig("dispute", "status")), "amount_cents" => charge.dig("dispute", "amount") }
    )
    announce(payment, overpaid:) if created
    payment
  end

  def refund!(account, intent_id, refunded_cents:)
    payment = recorded_payment(account, intent_id) or return
    payment, reopened = payment.invoice.reflect_refund!(payment, refunded_cents: refunded_cents.to_i)
    warn_reopened(payment, "a refund") if reopened
    payment
  end

  def dispute!(account, intent_id, stripe_status:, amount_cents:)
    payment = recorded_payment(account, intent_id) or return
    status = dispute_status(stripe_status)
    changed = payment.dispute_status != status
    payment, reopened = payment.invoice.reflect_dispute!(payment, status:, amount_cents: amount_cents.to_i)
    notify_dispute(payment) if changed && status == "open"
    warn_reopened(payment, "a lost dispute") if reopened
    payment
  end

  # Our payment for a PaymentIntent; nil when it's one of the business's other Stripe charges.
  # Ours but not recorded yet (its notification is late or failed): raises, to be retried.
  def recorded_payment(account, intent_id)
    return if intent_id.blank?

    Payment.find_by(provider_payment_id: intent_id.to_s) || begin
      metadata = PaymentGateway.current.payment_details(account.account_id, intent_id.to_s)["metadata"] || {}
      raise PaymentNotRecordedYet, "Payment #{intent_id} isn't recorded yet" if metadata["shadetree_business"] == account.business.uid

      nil
    end
  end

  # How the payment was made and what's happened to it since, from Stripe; empty if Stripe can't
  # say (the payment is still recorded, with just its method).
  def charge_details(account, intent_id)
    PaymentGateway.current.payment_details(account.account_id, intent_id)
  rescue PaymentGateway::Error => error
    Rails.error.report(error, handled: true, context: { payment_account: account.uid })
    {}
  end

  # "Visa ending 4242 (Apple Pay)", for the receipt and the invoice.
  def method_detail(charge)
    return if charge["last4"].blank?

    brand = BRANDS.fetch(charge["brand"].to_s) { charge["brand"].to_s.titleize.presence || "Card" }
    wallet = WALLETS[charge["wallet"].to_s]
    "#{brand} ending #{charge["last4"]}#{" (#{wallet})" if wallet}"
  end

  def admin_path(invoice) = Rails.application.routes.url_helpers.admin_invoice_path(invoice)

  # The client's receipt, and the team's notification (about the invoice, so erasing the client
  # scrubs it, INS-02); a warning too if it paid more than was owed.
  def announce(payment, overpaid: 0)
    invoice = payment.invoice
    send_receipt(payment)
    amount = Money.new(payment.amount_cents, payment.currency).format
    left = invoice.paid? ? "Paid in full." : "#{invoice.balance.format} left to pay."
    NotificationType.deliver("online_payment", business: invoice.business, subject: invoice,
                             title: "#{invoice.client.display_name} paid #{amount} online for invoice #{invoice.number}", body: left, path: admin_path(invoice))
    return unless overpaid.positive?

    extra = Money.new(overpaid, payment.currency).format
    NotificationType.deliver("payment_attention", business: invoice.business, subject: invoice,
                             title: invoice.void? ? "Invoice #{invoice.number} was paid online after it was voided" : "Invoice #{invoice.number} was overpaid by #{extra}",
                             body: "Refund #{extra} to the client in your Stripe dashboard.", path: admin_path(invoice))
  end

  # A refund or lost dispute took an invoice back to awaiting payment: the client isn't chased
  # for it by overdue automations, and the team decides (void it, or follow up).
  def warn_reopened(payment, cause)
    invoice = payment.invoice
    Automation.skip_overdue_for(invoice, "Reopened after #{cause} in Stripe.")
    NotificationType.deliver("payment_attention", business: invoice.business, subject: invoice,
                             title: "Invoice #{invoice.number} is awaiting payment again after #{cause}",
                             body: "#{invoice.balance.format} shows as owed. Void the invoice, or follow up with the client. Overdue automations won't chase it.",
                             path: admin_path(invoice))
  end

  # To the client's email on file, unless they have none, were erased, or the business can't
  # email clients yet (its owner hasn't confirmed their email, ACC-01). Over the hourly cap it
  # waits and tries again. The mailer itself skips suppressed addresses.
  RECEIPT_WAIT = 15.minutes

  def send_receipt(payment)
    client = payment.invoice.client
    to = client.primary_email&.value
    return if to.nil? || client.erased? || !payment.business.owner&.can_send_to_clients?
    return OnlineReceiptJob.set(wait: RECEIPT_WAIT).perform_later(payment.id) if EmailMessage.hourly_limit_reached?

    PaymentMailer.send_later(:receipt, business: payment.business, to:, kind: "payment_receipt", related: payment, payment_id: payment.id)
  end

  def notify_dispute(payment)
    invoice = payment.invoice
    NotificationType.deliver("payment_disputed", business: invoice.business, subject: invoice,
                             title: "#{invoice.client.display_name} disputed a #{Money.new(payment.amount_cents, payment.currency).format} payment on invoice #{invoice.number}",
                             body: "Respond in your Stripe dashboard before the deadline Stripe gives.", path: admin_path(invoice))
  end
end
