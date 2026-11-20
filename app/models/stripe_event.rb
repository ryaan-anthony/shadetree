# A Stripe event received at /webhooks/stripe (BIL-04, ADR 0021): only its id, type and the ids
# it's about, so each event is processed once however often Stripe sends it. The payload isn't
# kept; StripeEventJob fetches the object's current state from Stripe.
class StripeEvent < ApplicationRecord
  HANDLED = %w[
    checkout.session.completed customer.subscription.created customer.subscription.updated customer.subscription.deleted
    customer.subscription.paused customer.subscription.resumed invoice.paid invoice.payment_failed
  ].freeze

  scope :unprocessed, -> { where(processed_at: nil) }

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
