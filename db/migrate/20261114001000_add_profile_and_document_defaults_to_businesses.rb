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
    # The old free-text address becomes the first line; owners can tidy it up in settings.
    execute "UPDATE businesses SET address_line1 = left(regexp_replace(address, '\\s+', ' ', 'g'), 255) WHERE address IS NOT NULL"
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
