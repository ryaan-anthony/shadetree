class CreateNotificationTriggers < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_triggers do |t|
      t.references :business, null: false, foreign_key: true
      t.references :message_template, null: false, foreign_key: true
      t.string :trigger_name, null: false
      t.string :trigger_event, null: false
      t.json :trigger_conditions, default: {}
      t.integer :timing_offset, default: 0
      t.boolean :is_active, default: true
      t.json :delivery_channels, default: {}
      t.datetime :last_triggered_at
      t.integer :trigger_count, default: 0

      t.timestamps
    end

    # Add indexes for common queries
    add_index :notification_triggers, [:business_id, :trigger_event]
    add_index :notification_triggers, [:business_id, :is_active]
  end
end
