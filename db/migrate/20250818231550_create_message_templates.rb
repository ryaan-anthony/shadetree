class CreateMessageTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :message_templates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :event, null: false
      t.string :message_type, null: false
      t.text :message_content, null: false
      t.string :subject_line
      t.boolean :is_active, default: true
      t.integer :usage_count, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :message_templates, [ :business_id, :event ]
    add_index :message_templates, [ :business_id, :message_type ]
  end
end
