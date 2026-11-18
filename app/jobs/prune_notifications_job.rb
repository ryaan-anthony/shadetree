# NTF-02: deletes team notifications older than Notification::RETENTION. Runs daily
# (config/recurring.yml).
class PruneNotificationsJob < ApplicationJob
  queue_as :default

  def perform = Notification.prune!
end
