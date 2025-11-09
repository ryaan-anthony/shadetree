class CreateServicePrices < ActiveRecord::Migration[8.0]
  def change
    create_table :service_prices do |t|
      # Service and location relationships
      t.references :service, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true

      # Pricing information
      t.decimal :base_price, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD'
      t.date :effective_date
      t.date :expires_date

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :service_prices, :effective_date
    add_index :service_prices, :expires_date
    add_index :service_prices, :currency
    add_index :service_prices, [ :service_id, :location_id ], unique: true, name: 'index_service_prices_on_service_and_location'
  end
end
