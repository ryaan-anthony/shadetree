# NTF-05 (ADR 0028): late bounces and complaints. Only what the app acts on is kept: never the
# address, the server's diagnostic text or the payload.
class CreateEmailEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :email_events do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :email_message, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_key, null: false, index: { unique: true } # the event's id, else a digest of what was posted
      t.string :event_type, null: false
      t.string :status_code
      t.string :reply_code
      t.string :reason, null: false
      t.string :recipient_role, null: false
      t.integer :cc_position # which of the send's CCs, counted from 0
      t.datetime :occurred_at, null: false
      t.datetime :processed_at
      t.timestamps
      t.index :created_at
      t.check_constraint "event_type IN ('bounce', 'complaint')", name: "email_events_type"
      t.check_constraint "recipient_role IN ('to', 'cc')", name: "email_events_role"
    end

    # What arrived each day, matched or not: counts only (the ops console's Email events card).
    create_table :email_event_tallies do |t|
      t.date :day, null: false, index: { unique: true }
      t.integer :received, null: false, default: 0
      t.integer :matched, null: false, default: 0
      t.integer :dropped, null: false, default: 0
    end

    # A CC that bounced or complained, for the send history (the email itself stays delivered).
    add_column :email_messages, :cc_problems, :jsonb, null: false, default: []
  end
end
