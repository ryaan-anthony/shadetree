# What each Stripe Connect notification does (PAY-03, PAY-04), run by ConnectEvent#process! as
# the business whose account it's about. Each handler is idempotent (a status copy; a payment
# keyed by its Stripe id), so running one twice changes nothing. Returns "processed" or
# "ignored": events from the other mode (test vs live), for accounts no business has connected,
# and of types we don't act on are ignored.
class ConnectEventHandler
  HANDLERS = {
    "account.updated" => :account_updated,
    "account.application.deauthorized" => :account_deauthorized,
    # PAY-04: payments, refunds and disputes on invoices paid online
    "checkout.session.completed" => :checkout_completed,
    "checkout.session.async_payment_succeeded" => :checkout_completed,
    "payment_intent.succeeded" => :payment_succeeded,
    "charge.refunded" => :charge_refunded,
    "charge.dispute.created" => :dispute_changed,
    "charge.dispute.updated" => :dispute_changed,
    "charge.dispute.closed" => :dispute_changed
  }.freeze

  def self.handle(event) = new(event).handle

  def initialize(event)
    @event = event
  end

  def handle
    handler = HANDLERS[@event.event_type]
    return "ignored" unless handler && @event.livemode == PaymentGateway.live_mode?

    account = PaymentAccount.for_account(@event.account_id)
    return "ignored" unless account

    Tenancy.with_business(account.business) { send(handler, account) }
    "processed"
  end

  private

  def object = @event.data

  # Only for the account itself, and not when the status already came from a later event.
  def account_updated(account)
    return if object["id"].present? && object["id"] != account.account_id
    return if account.status_event_at && @event.event_created_at && @event.event_created_at < account.status_event_at

    account.sync!(object, at: @event.event_created_at)
  end

  # The business disconnected Shadetree from its Stripe dashboard.
  def account_deauthorized(account) = account.disconnect!(reason: "provider")

  def checkout_completed(account)
    return unless object["payment_status"] == "paid"

    OnlinePayments.record!(account, intent_id: object["payment_intent"], amount_cents: object["amount_total"], currency: object["currency"],
                                    metadata: object["metadata"], checkout_id: object["id"])
  end

  def payment_succeeded(account)
    OnlinePayments.record!(account, intent_id: object["id"], amount_cents: object["amount_received"], currency: object["currency"], metadata: object["metadata"])
  end

  def charge_refunded(account) = OnlinePayments.refund!(account, object["payment_intent"], refunded_cents: object["amount_refunded"])

  def dispute_changed(account) = OnlinePayments.dispute!(account, object["payment_intent"], stripe_status: object["status"], amount_cents: object["amount"])
end
