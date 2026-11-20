# What a Stripe event means for a business (BIL-04/05, ADR 0022). The event only says what
# changed; the current state is fetched from Stripe, so duplicates and out-of-order events
# leave the same result. Events for customers that aren't a business here are ignored.
class Billing::EventProcessor
  def self.process!(event) = new(event).process!

  def initialize(event)
    @event = event
  end

  def process!
    business = @event.customer_id && Business.find_by(stripe_customer_id: @event.customer_id)
    return unless business

    case @event.event_type
    when "checkout.session.completed"
      session = gateway.retrieve_checkout_session(@event.stripe_object_id)
      if session.client_reference_id.present? && session.client_reference_id != business.uid
        raise Billing::SubscriptionSync::Mismatch, "Checkout session #{session.id} names another business"
      end

      subscription = session.subscription.respond_to?(:id) ? session.subscription.id : session.subscription
      Billing::SubscriptionSync.refresh!(business, subscription) if subscription
    when /\Acustomer\.subscription\./
      Billing::SubscriptionSync.refresh!(business, @event.stripe_object_id)
    when "invoice.paid", "invoice.payment_failed"
      invoice = gateway.retrieve_invoice(@event.stripe_object_id)
      record_invoice(business, invoice)
      subscription = invoice.parent&.subscription_details&.subscription
      subscription = subscription.id if subscription.respond_to?(:id)
      Billing::SubscriptionSync.refresh!(business, subscription) if subscription
    end
  rescue Billing::SubscriptionSync::Mismatch => error
    # Never mirrored; an operator looks into it. The event is done (trying again can't help).
    Rails.error.report(error, handled: true, context: { stripe_event_id: @event.stripe_event_id, business_id: business&.id })
  end

  private

  def gateway = Billing.gateway

  def record_invoice(business, invoice)
    details = { "invoice" => invoice.number, "currency" => invoice.currency }
    Tenancy.with_business(business) do
      if @event.event_type == "invoice.paid"
        next if invoice.amount_paid.to_i.zero? # nothing was charged (a free trial or a full discount)

        BillingEvent.record!("payment_succeeded", details: details.merge("amount_cents" => invoice.amount_paid),
                                                  dedupe_key: "paid:#{invoice.id}", at: @event.stripe_created_at)
      else
        BillingEvent.record!("payment_failed", details: details.merge("amount_cents" => invoice.amount_due, "attempt" => invoice.attempt_count),
                                               dedupe_key: "failed:#{invoice.id}:#{invoice.attempt_count}", at: @event.stripe_created_at)
      end
    end
  end
end
