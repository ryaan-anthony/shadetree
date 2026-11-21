# BIL-05: emails a business's Owners as its trial nears its end: DAYS before (3 days, then 1),
# each once, from HOUR in the morning of that day in the business's time zone (as visit
# reminders are). A business that has subscribed (or is comped) gets none.
module Billing::TrialReminders
  DAYS = [ 3, 1 ].freeze
  HOUR = 9

  # When the "ends in N days" email is due: HOUR on the local date N days before the end.
  def self.due_at(business, days)
    date = (business.trial_ends_at - days.days).in_time_zone(business.time_zone).to_date
    business.local_time(date, "#{HOUR}:00")
  end

  def self.send_due!(business, at: Time.current)
    return unless business.billing_status == "trialing" && business.trial_ends_at && business.trial_ends_at > at

    days = DAYS.select { due_at(business, _1) <= at }.min or return
    return if business.trial_reminded_days && business.trial_reminded_days <= days

    business.update_columns(trial_reminded_days: days)
    BillingMailer.notify_owners(business, :trial_ending, days_left: ((business.trial_ends_at - at) / 1.day).ceil)
  end
end
