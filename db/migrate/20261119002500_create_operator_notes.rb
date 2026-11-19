# OPS-02: operators' internal notes on a business. Never shown to the business.
class CreateOperatorNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_notes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify } # kept if the author is removed
      t.text :body, null: false
      t.timestamps
    end
  end
end
