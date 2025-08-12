class CreateBusinessClosures < ActiveRecord::Migration[8.0]
  def change
    create_table :business_closures do |t|
      # Location relationship
      t.references :location, null: false, foreign_key: true

      # Closure configuration
      t.date :date, null: false
      t.string :reason, null: false
      t.boolean :is_full_day, default: true
      t.time :modified_open_time
      t.time :modified_close_time
      t.boolean :is_recurring, default: false

      t.timestamps
    end

    # Add indexes for better query performance
    add_index :business_closures, :date
    add_index :business_closures, :is_recurring
    add_index :business_closures, [:location_id, :date], unique: true, name: 'index_business_closures_on_location_and_date'
  end
end
