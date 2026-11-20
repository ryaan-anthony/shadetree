# A Stripe event received at /webhooks/stripe (BIL-04, ADR 0022): only its id, type and the ids
# it's about, so each event is processed once however often Stripe sends it. The payload isn't
# kept; StripeEventJob fetches the object's current state from Stripe.
class StripeEvent < ApplicationRecord
  HANDLED = %w[
    checkout.session.completed customer.subscription.created customer.subscription.updated customer.subscription.deleted
    customer.subscription.paused customer.subscription.resumed invoice.paid invoice.payment_failed
  ].freeze

  MAX_ATTEMPTS = 8

  scope :unprocessed, -> { where(processed_at: nil) }

  # Events the sweep should try again: not given up on, and not tried within their backoff
  # (2, 4, 8 … minutes after the last attempt).
  def self.due_for_retry(now: Time.current)
    unprocessed.where(attempts: ...MAX_ATTEMPTS).where(created_at: ..10.minutes.ago)
               .where("last_attempted_at IS NULL OR last_attempted_at <= ?::timestamp - (interval '1 minute' * power(2, attempts))", now)
  end

  # Processes the event (Billing::EventProcessor), counting the attempt. After MAX_ATTEMPTS
  # failures it's given up on with a single report. Re-raises the failure for the caller.
  def process!
    return if processed_at

    update_columns(attempts: attempts + 1, last_attempted_at: Time.current)
    Billing::EventProcessor.process!(self)
    update_columns(processed_at: Time.current)
  rescue StandardError
    if attempts >= MAX_ATTEMPTS
      Observability.alert("Gave up on a Stripe event after #{attempts} attempts", stripe_event_id:, event_type:)
    end
    raise
  end

  # Stores a verified event and queues its processing; a duplicate (or an event type we don't
  # use) is accepted and ignored. Returns the new row, or nil.
  def self.receive!(event)
    return unless HANDLED.include?(event.type)

    object = event.data.object
    customer = object.respond_to?(:customer) ? object.customer : nil
    customer = customer.id if customer.respond_to?(:id)
    result = insert_all([ { stripe_event_id: event.id, event_type: event.type, stripe_object_id: object.id, customer_id: customer,
                            livemode: event.livemode == true, stripe_created_at: Time.zone.at(event.created), created_at: Time.current } ],
                        unique_by: :stripe_event_id, returning: %i[id])
    return if result.rows.empty?

    find(result.rows.first.first).tap { StripeEventJob.perform_later(_1.id) }
  end
end
