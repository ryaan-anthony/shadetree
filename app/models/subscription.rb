# A business's Stripe subscription (BIL-04, ADR 0022), as Stripe last described it. Written only
# by Billing::SubscriptionSync from what Stripe returns; the business's plan follows from it
# (Billing::PlanResolver). One per business: a new subscription after an old one ended takes
# its place.
class Subscription < ApplicationRecord
  include BusinessOwned

  # Stripe statuses that keep the paid plan: paying, trialing, or a failed renewal being retried.
  LIVE_STATUSES = %w[active trialing past_due].freeze
  STATUS_LABELS = {
    "active" => "Active", "trialing" => "Trialing", "past_due" => "Past due", "unpaid" => "Unpaid", "canceled" => "Canceled",
    "incomplete" => "Waiting for payment", "incomplete_expired" => "Expired", "paused" => "Paused"
  }.freeze

  belongs_to :plan, optional: true

  validates :stripe_subscription_id, :status, presence: true

  def live? = LIVE_STATUSES.include?(status)
  def past_due? = status == "past_due"
  def status_label = STATUS_LABELS.fetch(status, status.humanize)
  def yearly? = interval == "yearly"

  # What the business pays each interval for its plan (the list price; Stripe applies any
  # discount and tax).
  def price = plan && Money.new(plan.price_cents(interval), plan.currency)
end
