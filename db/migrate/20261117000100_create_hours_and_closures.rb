# CAT-06: a business's weekly hours and its closures (holidays, vacation, a half day).
#
# Weekly hours are one open range per weekday, kept on the business as
# { "1" => { "opens" => "08:00", "closes" => "17:00" }, … } keyed by Date#wday; a weekday
# missing from the hash is closed. NULL means the hours have never been set, so scheduling
# neither shades nor warns.
#
# A closure covers a date or a date range, all day or between two times on each of those
# days, and can repeat every year (on the same month and day).
class CreateHoursAndClosures < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :weekly_hours, :jsonb

    create_table :closures do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false
      t.string :reason, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :start_minute # minutes after local midnight; both set for part of a day
      t.integer :end_minute
      t.boolean :repeats_yearly, null: false, default: false
      t.timestamps
      t.check_constraint "ends_on >= starts_on", name: "closures_date_order"
      t.check_constraint "(start_minute IS NULL) = (end_minute IS NULL) AND (start_minute IS NULL OR (start_minute >= 0 AND start_minute < end_minute AND end_minute <= 1440))", name: "closures_minutes"
    end
    add_index :closures, :uid, unique: true
    add_index :closures, %i[business_id ends_on]
  end
end
