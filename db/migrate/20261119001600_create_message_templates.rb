# NTF-03: a business's own wording for a client-facing email (kind), or an extra template of
# its own (no kind, a name) for automations and manual sends.
class CreateMessageTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :message_templates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :uid, null: false
      t.string :kind
      t.string :name
      t.string :subject, null: false
      t.text :body, null: false
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :message_templates, :uid, unique: true
    add_index :message_templates, %i[business_id kind], unique: true, where: "kind IS NOT NULL"
  end
end
