# PAY-03/PAY-04: Stripe's notifications about connected accounts (account status, payments,
# refunds, disputes), one row per event id so a repeated delivery is never processed twice.
# Only the fields the app acts on are kept (no names, emails or card details), and the rows
# are pruned after a while (PruneConnectEventsJob). attempts counts tries, so the sweeper
# (RetryConnectEventsJob) gives up on one that keeps failing.
class CreateConnectEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :connect_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :account_id
      t.boolean :livemode, null: false, default: false
      t.datetime :event_created_at
      t.integer :attempts, null: false, default: 0
      t.jsonb :data, null: false, default: {}
      t.string :status, null: false, default: "received"
      t.string :error
      t.datetime :processed_at
      t.timestamps

      t.index :event_id, unique: true
      t.index :created_at
      t.index %i[status updated_at], where: "status IN ('received', 'failed')", name: "index_connect_events_to_retry"
      t.check_constraint "status IN ('received', 'processed', 'ignored', 'failed')", name: "connect_events_status"
    end
  end
end
