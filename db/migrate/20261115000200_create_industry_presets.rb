# CAT-05: starter services per industry. Global reference data (no business), editable by
# operators without a deploy.
class CreateIndustryPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :industry_presets do |t|
      t.string :industry, null: false, index: { unique: true }
      t.integer :default_visit_minutes, null: false, default: 60
      t.jsonb :items, null: false, default: []
      t.timestamps
    end
  end
end
