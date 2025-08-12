class CreateServiceFees < ActiveRecord::Migration[8.0]
  def change
    create_table :service_fees do |t|
      # Service and location relationships
      t.references :service, null: false, foreign_key: true
      t.references :location, null: true, foreign_key: true

      # Fee configuration
      t.string :fee_name, null: false
      t.decimal :fee_amount, precision: 8, scale: 4, null: false
      t.string :fee_type, null: false
      t.boolean :is_mandatory, default: true

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :service_fees, :fee_type
    add_index :service_fees, :is_mandatory
    add_index :service_fees, [:service_id, :location_id, :fee_name], unique: true, name: 'index_service_fees_on_service_location_name'
  end
end
