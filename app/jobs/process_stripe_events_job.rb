# BIL-04: a safety net for Stripe events whose processing never finished (a deploy, retries run
# out): every 15 minutes, events received more than 10 minutes ago and still unprocessed are run
# again, oldest first.
class ProcessStripeEventsJob < ApplicationJob
  queue_as :default

  def perform
    StripeEvent.unprocessed.where(created_at: ..10.minutes.ago).order(:created_at).limit(500).pluck(:id).each do |id|
      StripeEventJob.perform_now(id)
    rescue StandardError => error
      Rails.error.report(error, context: { stripe_event_id: id })
    end
  end
end
