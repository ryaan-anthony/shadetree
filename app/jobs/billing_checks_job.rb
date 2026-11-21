# BIL-05: every hour, businesses whose plan time alone changes (a trial, comp or grace period
# ending, a cancelled plan reaching the end of its paid period) or that are due a trial
# reminder: each is worked out again under its lock. Idempotent; one failing doesn't stop the rest.
class BillingChecksJob < ApplicationJob
  queue_as :default

  def perform
    cancel_for_closed_businesses
    Business.where(billing_check_at: ..Time.current).order(:billing_check_at).limit(1000).pluck(:id).each do |id|
      business = Business.find(id)
      business.with_lock do
        Billing::TrialReminders.send_due!(business)
        Billing::PlanResolver.apply!(business)
      end
    rescue StandardError => error
      Rails.error.report(error, context: { business_id: id })
    end
  end

  private

  # ACC-06's safety net: a closed business (its last Owner deleted their account) whose
  # subscription is still live gets it cancelled again.
  def cancel_for_closed_businesses
    Business.where(active: false, suspended_at: nil, billing_status: %w[active past_due]).where.not(stripe_customer_id: nil)
            .pluck(:id).each { CancelSubscriptionsJob.perform_later(_1) }
  end
end
