# PLT-11: runtime state for release flags. Which flags exist (and who owns them) is declared in
# config/feature_flags.yml; this table only holds how each one is currently set.
class CreateFeatureFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_flags do |t|
      t.string :name, null: false
      t.string :state, null: false, default: "off"
      t.integer :percentage, null: false, default: 0
      t.bigint :business_ids, array: true, null: false, default: []
      t.string :changed_by
      t.timestamps
    end
    add_index :feature_flags, :name, unique: true
  end
end
