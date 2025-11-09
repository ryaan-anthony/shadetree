class CreateOperatingHours < ActiveRecord::Migration[8.0]
  def change
    create_table :operating_hours do |t|
      # Location relationship
      t.references :location, null: false, foreign_key: true

      # Operating hours configuration
      t.integer :day_of_week, null: false
      t.time :open_time
      t.time :close_time
      t.boolean :is_closed, default: false

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :operating_hours, :day_of_week
    add_index :operating_hours, [ :location_id, :day_of_week ], unique: true, name: 'index_operating_hours_on_location_and_day'
  end
end
