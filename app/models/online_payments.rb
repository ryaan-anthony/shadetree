# PAY-04: clients paying invoices online, through Stripe Checkout on the business's own Stripe
# account (a direct charge; ADR 0021). Starting a payment (checkout_session_params) and acting on
# what Stripe confirms afterwards (record!, refund!, dispute!), called by
# ProcessConnectEventJob as the business. The browser's return is never taken as proof.
module OnlinePayments
  module_function

  # The smallest part payment a client may choose (when the business allows them).
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
      success_url:, cancel_url:, expires_at: 1.hour.from_now.to_i }
  end

  # A confirmed payment (a Checkout Session paid, or its PaymentIntent succeeded). Returns the
  # Payment, or nil when it isn't for an invoice of this account's business.
  def record!(account, intent_id:, amount_cents:, currency:, metadata:, checkout_id: nil)
    metadata ||= {}
    return if intent_id.blank? || amount_cents.to_i <= 0 || metadata["shadetree_business"] != account.business.uid

    invoice = Invoice.find_by(uid: metadata["shadetree_invoice"].to_s)
    return unless invoice && invoice.currency == currency.to_s.upcase
    return Payment.find_by(provider_payment_id: intent_id) if Payment.exists?(provider_payment_id: intent_id)

    payment, created = invoice.record_online_payment!(intent_id:, amount_cents: amount_cents.to_i, currency:, checkout_id:,
                                                      method_detail: method_detail(account, intent_id),
                                                      platform_fee_cents: metadata["shadetree_fee_cents"].to_i)
    announce(payment) if created
    payment
  end

  def refund!(intent_id, refunded_cents:)
    payment = Payment.find_by(provider_payment_id: intent_id.to_s) or return
    payment.invoice.reflect_refund!(payment, refunded_cents: refunded_cents.to_i)
  end

  def dispute!(intent_id, stripe_status:, amount_cents:)
    payment = Payment.find_by(provider_payment_id: intent_id.to_s) or return
    status = case stripe_status
    when "won", "warning_closed" then "won"
    when "lost" then "lost"
    else "open"
    end
    changed = payment.dispute_status != status
    payment.invoice.reflect_dispute!(payment, status:, amount_cents: amount_cents.to_i)
    notify_dispute(payment) if changed && status == "open"
    payment
  end

  # "Visa ending 4242 (Apple Pay)", for the receipt and the invoice; just the method if Stripe
  # can't say.
  def method_detail(account, intent_id)
    details = PaymentGateway.current.payment_details(account.account_id, intent_id)
    return if details["last4"].blank?

    brand = BRANDS.fetch(details["brand"].to_s) { details["brand"].to_s.titleize.presence || "Card" }
    wallet = WALLETS[details["wallet"].to_s]
    "#{brand} ending #{details["last4"]}#{" (#{wallet})" if wallet}"
  rescue PaymentGateway::Error => error
    Rails.error.report(error, handled: true, context: { payment_account: account.uid })
    nil
  end

  # The client's receipt, and the team's notification.
  def announce(payment)
    invoice = payment.invoice
    send_receipt(payment)
    amount = Money.new(payment.amount_cents, payment.currency).format
    left = invoice.paid? ? "Paid in full." : "#{invoice.balance.format} left to pay."
    NotificationType.deliver("online_payment", business: invoice.business, subject: payment,
                             title: "#{invoice.client.display_name} paid #{amount} online for invoice #{invoice.number}", body: left,
                             path: Rails.application.routes.url_helpers.admin_invoice_path(invoice))
  end

  # To the client's email on file, unless they have none, were erased, or the business can't
  # email clients yet (its owner hasn't confirmed their email, ACC-01) or has sent too many
  # this hour. The mailer itself skips suppressed addresses.
  def send_receipt(payment)
    client = payment.invoice.client
    to = client.primary_email&.value
    return if to.nil? || client.erased? || !payment.business.owner&.can_send_to_clients? || EmailMessage.hourly_limit_reached?

    PaymentMailer.send_later(:receipt, business: payment.business, to:, kind: "payment_receipt", related: payment, payment_id: payment.id)
  end

  def notify_dispute(payment)
    invoice = payment.invoice
    NotificationType.deliver("payment_disputed", business: invoice.business, subject: payment,
                             title: "#{invoice.client.display_name} disputed a #{Money.new(payment.amount_cents, payment.currency).format} payment on invoice #{invoice.number}",
                             body: "Respond in your Stripe dashboard before the deadline Stripe gives.",
                             path: Rails.application.routes.url_helpers.admin_invoice_path(invoice))
  end
end
