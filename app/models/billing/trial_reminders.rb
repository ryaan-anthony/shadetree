# BIL-05: emails a business's Owners as its trial nears its end: DAYS before (3 days, then 1),
# each once. A business that has subscribed (or is comped) gets none.
module Billing::TrialReminders
  DAYS = [ 3, 1 ].freeze

  def self.send_due!(business, at: Time.current)
    return unless business.billing_status == "trialing" && business.trial_ends_at && business.trial_ends_at > at

    days = DAYS.select { business.trial_ends_at - _1.days <= at }.min or return
    return if business.trial_reminded_days && business.trial_reminded_days <= days

    business.update_columns(trial_reminded_days: days)
    BillingMailer.notify_owners(business, :trial_ending, days_left: ((business.trial_ends_at - at) / 1.day).ceil)
  end
end
