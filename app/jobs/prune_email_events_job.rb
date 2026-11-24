# NTF-05: late bounce and complaint events are only kept to spot repeats and to look into a
# problem, so they go after EmailEvent::KEPT_FOR; the email keeps what they changed.
class PruneEmailEventsJob < ApplicationJob
  queue_as :default

  def perform
    Tenancy.across_businesses(reason: "NTF-05: prune old bounce events") { EmailEvent.prunable.in_batches.delete_all }
    EmailEventTally.where(day: ...EmailEvent::KEPT_FOR.ago.to_date).delete_all
  end
end
