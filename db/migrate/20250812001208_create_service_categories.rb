class CreateServiceCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :service_categories do |t|
      # Business relationship
      t.references :business, null: false, foreign_key: true

      # Category information
      t.string :name, null: false
      t.text :description
      t.references :parent, null: true, foreign_key: { to_table: :service_categories }
      t.integer :sort_order, default: 0
      t.boolean :active, default: true

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :service_categories, :active
    add_index :service_categories, :sort_order
    add_index :service_categories, [ :business_id, :parent_id, :name ], unique: true, name: 'index_service_categories_on_business_parent_name'
  end
end
