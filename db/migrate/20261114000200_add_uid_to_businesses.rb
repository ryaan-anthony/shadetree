# Opaque identifiers for businesses in URLs and forms, so ids don't reveal how many businesses
# exist (ADR 0014). Business-owned tables get the same `uid` column as they are created.
class AddUidToBusinesses < ActiveRecord::Migration[8.1]
  def up
    add_column :businesses, :uid, :string
    execute <<~SQL
      UPDATE businesses SET uid = substr(md5(random()::text || id::text), 1, 12) WHERE uid IS NULL
    SQL
    change_column_null :businesses, :uid, false
    add_index :businesses, :uid, unique: true
  end

  def down
    remove_column :businesses, :uid
  end
end
