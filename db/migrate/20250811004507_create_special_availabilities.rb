class CreateSpecialAvailabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :special_availabilities do |t|
      # Location relationship
      t.references :location, null: false, foreign_key: true

      # Special availability configuration
      t.date :date, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.string :reason, null: false

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :special_availabilities, :date
    add_index :special_availabilities, [ :location_id, :date ], unique: true, name: 'index_special_availabilities_on_location_and_date'
  end
end
