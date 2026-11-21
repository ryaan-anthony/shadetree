# Processes one stored Stripe Connect notification (ConnectEvent#process!). A failure is retried
# here with backoff, then by RetryConnectEventsJob every 10 minutes, up to
# ConnectEvent::MAX_ATTEMPTS tries in all; the event itself reports when it gives up.
class ProcessConnectEventJob < ApplicationJob
  queue_as :default
  # The sweeper carries on after these, so running out of retries here isn't an error.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |_job, _error|
  end

  def perform(connect_event_id) = ConnectEvent.find_by(id: connect_event_id)&.process!
end
