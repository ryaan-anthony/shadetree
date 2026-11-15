# CAT-03: what a business sells. Documents copy item values when items are added, so editing or
# archiving an item never changes an existing quote or invoice.
class CreateCatalog < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_categories do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :catalog_categories, :uid, unique: true
    add_index :catalog_categories, "business_id, lower(name)", unique: true, name: "index_catalog_categories_unique_name"

    create_table :catalog_items do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.references :category, foreign_key: { to_table: :catalog_categories, on_delete: :nullify }
      t.string :name, null: false
      t.text :description
      t.string :unit, null: false, default: "each"
      t.string :custom_unit
      t.integer :unit_price_cents # blank = price set on each quote
      t.boolean :taxable, null: false, default: true
      t.integer :duration_minutes
      t.boolean :show_on_request_form, null: false, default: true
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end
    add_index :catalog_items, :uid, unique: true
    add_index :catalog_items, [ :business_id, :archived_at, :position ]
  end
end
