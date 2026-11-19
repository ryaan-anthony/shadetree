# JOB-05: the day-before reminder. Each hour (VisitRemindersJob), a location (CAT-07) whose clock
# has passed Business::VISIT_REMINDER_HOUR reminds the clients of tomorrow's visits still
# booked there, once per visit (and again if the visit moves to another day). If the hourly runs miss
# the rest of that day, the reminder isn't sent late at night or on the day itself.
#
# A client emailed about the visit since midnight (booked or moved this morning) isn't also
# reminded; one whose email about it is still being put together (a change in the last few
# minutes) is looked at again next hour, when that email has gone.
class VisitReminders
  def self.send_due(business) = new(business).send_due

  def initialize(business)
    @business = business
  end

  # Returns the number of reminders queued. CAT-07: each location by its own clock and calendar
  # (archived ones too, for visits still booked there).
  def send_due
    return 0 unless @business.client_visit_email?("reminder")

    Location.all.each { _1.association(:business).target = @business }.sum do |location|
      next 0 if Time.current.in_time_zone(location.time_zone).hour < Business::VISIT_REMINDER_HOUR

      due = Visit.where(scheduled_on: location.today + 1, status: "scheduled", reminder_sent_at: nil)
                 .where(job_id: Job.where(location_id: location.id).select(:id)).includes(:job).to_a
      due.count { remind(_1, location) }
    end
  end

  private

  def remind(visit, location)
    return false if visit.job.client_notice_due_at || !visit.client_up_to_date? # an email about it is on its way: next hour

    to = visit.job.client.primary_email&.value or return false # no address yet: not claimed, so one added later still gets it
    # Claimed and queued in one transaction: a failure leaves it for the next hour, and two runs can't both send.
    visit.with_lock do
      next false unless visit.reminder_sent_at.nil? && visit.status == "scheduled"

      visit.update_columns(reminder_sent_at: Time.current)
      next false if emailed_today?(visit, location)

      VisitMailer.send_later(:reminder, business: @business, to:, kind: "visit_reminder", related: visit.job, job_id: visit.job_id, visit_id: visit.id)
      true
    end
  end

  def emailed_today?(visit, location)
    emailed_at = visit.client_told&.dig("emailed_at") or return false
    Time.iso8601(emailed_at) >= location.local_time(location.today, "00:00")
  end
end
