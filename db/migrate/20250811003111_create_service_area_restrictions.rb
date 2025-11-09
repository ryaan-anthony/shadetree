class CreateServiceAreaRestrictions < ActiveRecord::Migration[8.0]
  def change
    create_table :service_area_restrictions do |t|
      # Service area relationship
      t.references :service_area, null: false, foreign_key: true

      # Restriction configuration
      t.string :restriction_type, null: false
      t.string :city
      t.string :state
      t.string :zip_code
      t.text :reason

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :service_area_restrictions, :restriction_type
    add_index :service_area_restrictions, [ :restriction_type, :city ]
    add_index :service_area_restrictions, [ :restriction_type, :state ]
    add_index :service_area_restrictions, [ :restriction_type, :zip_code ]
  end
end
