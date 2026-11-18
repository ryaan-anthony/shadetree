# JOB-05: the hourly reminder run looks across businesses for booked visits not yet reminded.
class IndexVisitsForReminders < ActiveRecord::Migration[8.1]
  def change
    add_index :visits, :scheduled_on, name: "index_visits_awaiting_reminder", where: "status = 'scheduled' AND reminder_sent_at IS NULL"
  end
end
