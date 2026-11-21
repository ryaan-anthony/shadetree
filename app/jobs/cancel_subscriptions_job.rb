# BIL-04 / ACC-06: cancels a closed business's Stripe subscriptions, retrying while Stripe can't
# be reached. Stripe's events then move the business to Free.
class CancelSubscriptionsJob < ApplicationJob
  queue_as :default
  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 10

  def perform(business_id)
    business = Business.find_by(id: business_id)
    return unless business

    # Mirrored at once (BIL-05), so the hourly safety net doesn't ask again before the webhook.
    Billing.cancel_subscriptions!(business).each { Billing::SubscriptionSync.refresh!(business, _1) }
  end
end
