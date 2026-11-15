# CAT-01: structured address, country, and the document defaults quotes and invoices start from.
class AddProfileAndDocumentDefaultsToBusinesses < ActiveRecord::Migration[8.1]
  def up
    change_table :businesses, bulk: true do |t|
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :region
      t.string :postal_code
      t.string :country, null: false, default: "US"
      t.integer :quote_expiry_days, null: false, default: 30
      t.text :quote_terms
      t.integer :invoice_due_days, null: false, default: 14
      t.text :invoice_terms
      t.string :quote_number_prefix, null: false, default: "Q"
      t.string :invoice_number_prefix, null: false, default: "INV"
    end
    # The old free-text address moves over whole (these columns have no length limit in
    # Postgres): its first line becomes line 1 and any further lines become line 2. Owners can
    # tidy it into city, region and postal code in settings.
    execute <<~'SQL'
      UPDATE businesses SET
        address_line1 = nullif(btrim(split_part(btrim(address), E'\n', 1)), ''),
        address_line2 = nullif(btrim(regexp_replace(substr(btrim(address), length(split_part(btrim(address), E'\n', 1)) + 2), '\s*\n\s*', ', ', 'g')), '')
      WHERE nullif(btrim(address), '') IS NOT NULL
    SQL
    remove_column :businesses, :address
  end

  def down
    add_column :businesses, :address, :text
    execute "UPDATE businesses SET address = concat_ws(', ', address_line1, address_line2, city, region, postal_code)"
    change_table :businesses, bulk: true do |t|
      t.remove :address_line1, :address_line2, :city, :region, :postal_code, :country,
               :quote_expiry_days, :quote_terms, :invoice_due_days, :invoice_terms,
               :quote_number_prefix, :invoice_number_prefix
    end
  end
end
