# BIL-04: processes one Stripe event received by the webhook (Billing::EventProcessor). Stripe
# being unreachable is retried; ProcessStripeEventsJob picks up anything still unprocessed.
class StripeEventJob < ApplicationJob
  queue_as :default
  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 8

  def perform(stripe_event_id)
    event = StripeEvent.find_by(id: stripe_event_id)
    return if event.nil? || event.processed_at

    Billing::EventProcessor.process!(event)
    event.update!(processed_at: Time.current)
  end
end
