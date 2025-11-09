class CreateServiceTaxes < ActiveRecord::Migration[8.0]
  def change
    create_table :service_taxes do |t|
      # Service and location relationships
      t.references :service, null: false, foreign_key: true
      t.references :location, null: true, foreign_key: true

      # Tax configuration
      t.string :tax_name, null: false
      t.decimal :tax_rate, precision: 8, scale: 4, null: false
      t.string :tax_type, null: false
      t.boolean :is_inclusive, default: false

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :service_taxes, :tax_type
    add_index :service_taxes, :is_inclusive
    add_index :service_taxes, [ :service_id, :location_id, :tax_name ], unique: true, name: 'index_service_taxes_on_service_location_name'
  end
end
