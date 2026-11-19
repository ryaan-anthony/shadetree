# MKT-02: deletes contact messages past ContactMessage::RETENTION (spam sooner). Runs daily
# (config/recurring.yml).
class PruneContactMessagesJob < ApplicationJob
  queue_as :default

  def perform = ContactMessage.prune!
end
