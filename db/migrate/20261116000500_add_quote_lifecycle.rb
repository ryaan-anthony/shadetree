# QTE-06: archiving quotes, and a log of the staff actions on a quote that nothing else
# records (archived, restored, expiry extended, duplicated, revised), for its activity history.
class AddQuoteLifecycle < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :archived_at, :datetime
    add_index :quotes, %i[business_id archived_at created_at]

    create_table :quote_events do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.check_constraint "kind IN ('archived', 'unarchived', 'expiry_extended', 'duplicated', 'revised')", name: "quote_events_kind"
    end
    add_index :quote_events, %i[business_id quote_id occurred_at]
  end
end
