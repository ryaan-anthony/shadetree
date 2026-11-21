# BIL-04: a safety net for Stripe events whose processing never finished (a deploy, retries run
# out): every 15 minutes, events received more than 10 minutes ago, still unprocessed, not tried
# within their backoff and not given up on (StripeEvent::MAX_ATTEMPTS) are processed again,
# inline and oldest first.
class ProcessStripeEventsJob < ApplicationJob
  queue_as :default

  def perform
    StripeEvent.due_for_retry.order(:created_at).limit(500).each do |event|
      event.process!
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { stripe_event_id: event.stripe_event_id })
    end
  end
end
