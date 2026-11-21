# PAY-03: Stripe notifications are only needed to spot repeats and to look into a problem, so
# they're removed after ConnectEvent::KEPT_FOR (Stripe retries an event for three days at most).
class PruneConnectEventsJob < ApplicationJob
  queue_as :default

  def perform = ConnectEvent.prunable.in_batches.delete_all
end
