# PAY-04: closes an invoice's Checkout page after its balance changed (a payment recorded, the
# invoice voided or revised), so the client can't pay the old amount. One that was already paid
# is recorded from Stripe's notification as usual.
class ExpireCheckoutSessionJob < ApplicationJob
  queue_as :default
  retry_on PaymentGateway::Error, wait: :polynomially_longer, attempts: 5

  def perform(_invoice_id, session_id)
    account = Current.business&.payment_account or return

    PaymentGateway.current.expire_checkout_session(account.account_id, session_id)
  end
end
