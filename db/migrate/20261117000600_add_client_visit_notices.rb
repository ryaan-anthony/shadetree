# JOB-05: telling clients about their visits. A visit remembers what the client was last told
# (so a burst of edits becomes one email, or none if it ends where it started), a note meant
# for the client (instructions stay the crew's), and when the day-before reminder went. A job
# holds when its pending client email is due, so its visits' changes go out together.
class AddClientVisitNotices < ActiveRecord::Migration[8.1]
  def change
    change_table :visits, bulk: true do |t|
      t.text :client_note
      t.jsonb :client_told
      t.datetime :reminder_sent_at
    end
    add_column :jobs, :client_notice_due_at, :datetime
    add_column :businesses, :client_visit_emails, :jsonb, null: false, default: {}
    add_index :jobs, :client_notice_due_at, where: "client_notice_due_at IS NOT NULL"
  end
end
