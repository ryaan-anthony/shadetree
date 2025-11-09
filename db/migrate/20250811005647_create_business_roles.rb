class CreateBusinessRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :business_roles do |t|
      # Business relationship
      t.references :business, null: false, foreign_key: true

      # Role configuration
      t.string :name, null: false
      t.text :description
      t.json :permissions
      t.boolean :is_default, default: false

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :business_roles, :is_default
    add_index :business_roles, [ :business_id, :name ], unique: true, name: 'index_business_roles_on_business_and_name'
  end
end
