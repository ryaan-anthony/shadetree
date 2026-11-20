# Acts on one stored Stripe Connect notification (ConnectEvent), as the business whose account
# it's about. Safe to run twice: an event that's been handled isn't handled again, and each
# handler is idempotent on its own (a status copy, a payment keyed by its Stripe id). One that
# fails is marked failed and reported; Stripe's next delivery of it tries again.
# Events for accounts no business has connected, and types we don't act on, are ignored.
class ProcessConnectEventJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  HANDLERS = {
    "account.updated" => :account_updated,
    "account.application.deauthorized" => :account_deauthorized
  }.freeze

  def perform(connect_event_id)
    event = ConnectEvent.find_by(id: connect_event_id)
    return if event.nil? || event.status.in?(%w[processed ignored])

    handler = HANDLERS[event.event_type]
    account = PaymentAccount.for_account(event.account_id) if handler
    return event.finish!("ignored") unless handler && account

    Tenancy.with_business(account.business) { send(handler, event, account) }
    event.finish!("processed")
  rescue StandardError => error
    event&.finish!("failed", error: "#{error.class}: #{error.message}")
    raise
  end

  private

  def account_updated(event, account)
    # Only the account itself; an account.updated for another id would be a mix-up.
    account.sync!(event.object) if event.object["id"].blank? || event.object["id"] == account.account_id
  end

  # The business disconnected Shadetree from its Stripe dashboard.
  def account_deauthorized(_event, account) = account.disconnect!(reason: "provider")
end
