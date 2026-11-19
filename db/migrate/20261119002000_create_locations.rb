# CAT-07: a business's locations (branches, yards). Every business gets a primary location; its
# contact details, time zone and hours stay on the business profile. Closures without a location
# are the primary location's.
class CreateLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :locations do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false, index: { unique: true }
      t.string :name, null: false
      t.boolean :primary, null: false, default: false
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :region
      t.string :postal_code
      t.string :country, null: false, default: "US"
      t.string :phone
      t.string :email
      t.string :timezone
      t.jsonb :weekly_hours
      t.datetime :archived_at
      t.timestamps
      t.index %i[business_id name], unique: true
      t.index :business_id, unique: true, where: '"primary"', name: "index_locations_one_primary"
      t.check_constraint 'NOT ("primary" AND archived_at IS NOT NULL)', name: "locations_primary_active"
    end

    create_table :location_members do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :location, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
      t.index %i[location_id user_id], unique: true
      t.index %i[business_id user_id]
    end

    add_reference :closures, :location, foreign_key: { on_delete: :cascade }
    add_reference :business_users, :default_location, foreign_key: { to_table: :locations, on_delete: :nullify }
    add_column :business_users, :location_filter, :string # "all" or a location uid; NULL: never chosen

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO locations (business_id, uid, name, "primary", country, created_at, updated_at)
          SELECT id, substr(md5(random()::text || id::text), 1, 12), COALESCE(NULLIF(btrim(city), ''), 'Main location'), true, country, now(), now()
          FROM businesses
        SQL
      end
    end
  end
end
