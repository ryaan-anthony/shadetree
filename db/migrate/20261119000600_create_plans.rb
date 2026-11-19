# BIL-01: plans as data (prices, limits and features operators can change without a deploy),
# and each business's current plan, with per-business overrides (comped limits). Every
# business starts on, and existing ones move to, the default plan (Free).
class CreatePlans < ActiveRecord::Migration[8.1]
  def up
    create_table :plans do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :public, null: false, default: true
      t.boolean :default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.string :currency, null: false, default: "USD"
      t.bigint :monthly_price_cents, null: false, default: 0
      t.bigint :annual_price_cents, null: false, default: 0
      t.string :provider_monthly_price
      t.string :provider_annual_price
      # Limits by key ("quotes_sent", "team_members"…); a missing key or nil is unlimited.
      t.jsonb :limits, null: false, default: {}
      # Feature switches by key ("remove_powered_by", "message_templates"…).
      t.jsonb :features, null: false, default: {}
      t.timestamps

      t.index :key, unique: true
      t.index :default, unique: true, where: "\"default\"", name: "index_plans_one_default"
    end

    execute <<~SQL.squish
      INSERT INTO plans (key, name, description, "default", position, limits, features, created_at, updated_at)
      VALUES ('free', 'Free', 'Everything you need to quote, schedule and get paid.', true, 0,
              '{"quotes_sent": 5, "team_members": 2}', '{}', NOW(), NOW())
    SQL

    add_reference :businesses, :plan, foreign_key: true
    add_column :businesses, :plan_overrides, :jsonb, null: false, default: {}
    execute "UPDATE businesses SET plan_id = (SELECT id FROM plans WHERE key = 'free')"
    change_column_null :businesses, :plan_id, false
  end

  def down
    remove_column :businesses, :plan_overrides
    remove_reference :businesses, :plan
    drop_table :plans
  end
end
