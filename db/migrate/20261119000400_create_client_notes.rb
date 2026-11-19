# CLI-05: free-text notes staff add to a client's timeline; each can be edited by its author.
class CreateClientNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :client_notes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false
      t.references :client, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.text :body, null: false
      t.datetime :edited_at
      t.timestamps

      t.index %i[business_id uid], unique: true
    end
  end
end
