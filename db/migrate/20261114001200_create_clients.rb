# CLI-01: clients (never users, ADR/plan 04 D1), how to reach them, and where the work happens.
class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :display_name, null: false
      t.string :company_name
      t.text :notes
      t.string :tags, array: true, null: false, default: []
      t.boolean :tax_exempt, null: false, default: false
      t.datetime :archived_at
      t.timestamps
    end
    add_index :clients, :uid, unique: true
    add_index :clients, :tags, using: :gin

    # Emails and phones. `normalized` (lowercased email, digits-only phone) is what duplicate
    # suggestions and search (CLI-02) match on.
    create_table :client_contact_methods do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :client, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :value, null: false
      t.string :normalized, null: false
      t.string :label
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :client_contact_methods, [ :business_id, :kind, :normalized ]

    create_table :properties do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :client, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :label
      t.string :address_line1, null: false
      t.string :address_line2
      t.string :city
      t.string :region
      t.string :postal_code
      t.string :country, null: false, default: "US"
      t.text :access_notes
      t.boolean :billing, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :properties, :uid, unique: true
    add_index :properties, :client_id, unique: true, where: "billing", name: "index_properties_one_billing_per_client"
  end
end
