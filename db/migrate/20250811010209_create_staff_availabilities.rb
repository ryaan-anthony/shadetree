class CreateStaffAvailabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_availabilities do |t|
      # Staff member and location relationships
      t.references :staff_member, null: false, foreign_key: true
      t.references :location, null: true, foreign_key: true

      # Availability configuration
      t.integer :day_of_week, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.boolean :is_available, default: true

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :staff_availabilities, :day_of_week
    add_index :staff_availabilities, :is_available
    add_index :staff_availabilities, [ :staff_member_id, :day_of_week, :location_id ],
              unique: true, name: 'index_staff_availabilities_on_staff_day_location'
  end
end
