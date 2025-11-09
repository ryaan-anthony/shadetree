class CreateLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :locations do |t|
      # Business relationship
      t.references :business, null: false, foreign_key: true

      # Location information
      t.string :name, null: false
      t.string :timezone
      t.text :address, null: false
      t.string :city, null: false
      t.string :state, null: false
      t.string :zip_code, null: false

      # GPS coordinates
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      # Location settings
      t.boolean :is_primary, default: false
      t.string :phone
      t.string :email
      t.boolean :active, default: true

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :locations, [ :latitude, :longitude ]
    add_index :locations, :is_primary
    add_index :locations, :active
  end
end
