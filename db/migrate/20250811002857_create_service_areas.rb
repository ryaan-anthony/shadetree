class CreateServiceAreas < ActiveRecord::Migration[8.0]
  def change
    create_table :service_areas do |t|
      # Location relationship
      t.references :location, null: false, foreign_key: true

      # Service area configuration
      t.decimal :radius, precision: 8, scale: 2
      t.boolean :active, default: true

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :service_areas, :active
  end
end
