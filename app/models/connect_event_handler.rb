# What each Stripe Connect notification does (PAY-03, PAY-04), run by ConnectEvent#process! as
# the business whose account it's about. Each handler is idempotent (a status copy; a payment
# keyed by its Stripe id), so running one twice changes nothing. Returns "processed" or
# "ignored": events from the other mode (test vs live), for accounts no business has connected,
# and of types we don't act on are ignored.
class ConnectEventHandler
  HANDLERS = {
    "account.updated" => :account_updated,
    "account.application.deauthorized" => :account_deauthorized
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
end
