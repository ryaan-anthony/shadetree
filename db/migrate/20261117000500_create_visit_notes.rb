# JOB-04: notes the people on a visit add from their day view, and whether technicians see
# prices on the visits they're sent to.
class CreateVisitNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :technicians_see_prices, :boolean, null: false, default: false

    create_table :visit_notes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :visit, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.text :body, null: false
      t.timestamps
    end
  end
end
