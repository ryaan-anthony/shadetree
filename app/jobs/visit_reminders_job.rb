# JOB-05: hourly, every business with a booked visit tomorrow sends its day-before reminders
# once its own clock reaches the reminder hour (VisitReminders).
class VisitRemindersJob < ApplicationJob
  queue_as :default

  def perform
    window = (Date.current - 1)..(Date.current + 2) # "tomorrow" anywhere in the world
    ids = Tenancy.across_businesses(reason: "visit reminders: which businesses have visits soon") do
      Visit.where(status: "scheduled", reminder_sent_at: nil, scheduled_on: window).distinct.pluck(:business_id)
    end
    Business.where(id: ids).find_each do |business|
      next unless business.active?

      Tenancy.with_business(business) { VisitReminders.send_due(business) }
    rescue StandardError => e
      Rails.error.report(e, context: { business_id: business.id }) # one business's problem doesn't hold up the rest
    end
  end
end
