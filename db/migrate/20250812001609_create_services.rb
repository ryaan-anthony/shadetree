class CreateServices < ActiveRecord::Migration[8.0]
  def change
    create_table :services do |t|
      # Business and category relationships
      t.references :business, null: false, foreign_key: true
      t.references :service_category, null: false, foreign_key: true

      # Service information
      t.string :name, null: false
      t.text :description
      t.integer :duration, null: false
      t.boolean :requires_location, default: false
      t.boolean :is_active, default: true
      t.integer :sort_order, default: 0

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :services, :is_active
    add_index :services, :requires_location
    add_index :services, :sort_order
    add_index :services, [ :business_id, :name ], unique: true, name: 'index_services_on_business_and_name'
  end
end
