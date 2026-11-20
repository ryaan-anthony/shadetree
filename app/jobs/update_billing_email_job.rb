# BIL-04: after an Owner leaves a business (demoted, deactivated, or their account deleted), its
# Stripe customer's email becomes a remaining active Owner's, so receipts and Stripe's
# failed-payment emails reach someone who can act on them.
class UpdateBillingEmailJob < ApplicationJob
  queue_as :default
  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 10

  def perform(business_id)
    business = Business.find_by(id: business_id)
    return unless business&.stripe_customer_id

    owner = business.business_users.active.owners.includes(:user).order(:created_at).map(&:user).reject(&:deleted?).first
    Billing.gateway.update_customer(business.stripe_customer_id, email: owner.email) if owner
  end
end
