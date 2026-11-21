# PAY-03: Stripe notifications that failed, or were stored but never processed (the job was
# lost), are tried again every 10 minutes, inline, up to ConnectEvent::MAX_ATTEMPTS tries each.
# Stripe already has its 200 for them, so this is what makes processing reliable.
class RetryConnectEventsJob < ApplicationJob
  queue_as :default

  def perform
    ConnectEvent.due_for_retry.order(:id).limit(200).each do |event|
      event.process!
    rescue StandardError
      next # recorded on the event; it's tried again next time, or given up on
    end
  end
end
