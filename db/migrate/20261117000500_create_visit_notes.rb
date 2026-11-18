# JOB-04: notes the people on a visit add from their day view, and whether technicians see
# prices on the visits they're sent to.
class CreateVisitNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :technicians_see_prices, :boolean, null: false, default: false
    # When the office was last told the job is ready to invoice; cleared when a visit opens again.
    add_column :jobs, :ready_to_invoice_notified_at, :datetime

    create_table :visit_notes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :visit, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.text :body, null: false
      t.timestamps
    end
  end
end
