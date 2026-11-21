# BIL-04: processes one Stripe event received by the webhook (StripeEvent#process!, which counts
# attempts). Stripe being unreachable is retried here; ProcessStripeEventsJob picks up anything
# still unprocessed.
class StripeEventJob < ApplicationJob
  queue_as :default
  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 4

  def perform(stripe_event_id)
    event = StripeEvent.find_by(id: stripe_event_id)
    event.process! if event && event.attempts < StripeEvent::MAX_ATTEMPTS
  end
end
