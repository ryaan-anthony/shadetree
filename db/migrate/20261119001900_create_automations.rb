# NTF-04: a business's automation rules, every run of one (what triggered it, what ran or was
# skipped and why), and the record that keeps a client from getting the same automated message
# twice about one document.
class CreateAutomations < ActiveRecord::Migration[8.1]
  def change
    create_table :automation_rules do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :name, null: false
      t.string :trigger, null: false
      t.integer :delay_minutes, null: false, default: 0
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :actions, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.string :recipe
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :automation_rules, :uid, unique: true
    add_index :automation_rules, %i[business_id trigger], where: "enabled"

    create_table :automation_runs do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :rule, foreign_key: { to_table: :automation_rules, on_delete: :nullify }
      t.string :rule_name, null: false
      t.string :trigger, null: false
      t.references :subject, polymorphic: true, null: false
      t.string :status, null: false, default: "scheduled"
      t.datetime :run_at, null: false
      t.datetime :finished_at
      t.jsonb :log, null: false, default: []
      t.timestamps
    end
    add_index :automation_runs, %i[business_id created_at]
    add_index :automation_runs, %i[rule_id subject_type subject_id], unique: true, name: "index_automation_runs_once_per_subject"
    add_index :automation_runs, :run_at, where: "status = 'scheduled'", name: "index_automation_runs_scheduled"

    create_table :automation_deliveries do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :message_template, null: false, foreign_key: { on_delete: :cascade }
      t.references :subject, polymorphic: true, null: false
      t.datetime :created_at, null: false
    end
    add_index :automation_deliveries, %i[message_template_id subject_type subject_id], unique: true, name: "index_automation_deliveries_once"
  end
end
