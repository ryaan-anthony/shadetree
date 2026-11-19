# CAT-08: a catalog item's price at a location, overriding the business price there, and each
# location's own default tax rates (NULL: the business's defaults).
class CreateLocationPrices < ActiveRecord::Migration[8.1]
  def change
    create_table :location_prices do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :location, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :catalog_item, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :unit_price_cents, null: false
      t.timestamps
      t.index %i[location_id catalog_item_id], unique: true
      t.index %i[business_id catalog_item_id]
      t.check_constraint "unit_price_cents >= 0", name: "location_prices_not_negative"
    end

    add_column :locations, :tax_rate_ids, :bigint, array: true
  end
end
