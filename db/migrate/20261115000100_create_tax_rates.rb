# CAT-04: named tax rates. Documents copy a rate's name and percent when created, so editing
# or archiving a rate never changes an existing quote or invoice.
class CreateTaxRates < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_rates do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :name, null: false
      t.decimal :percent, precision: 7, scale: 4, null: false
      t.boolean :applies_by_default, null: false, default: true
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
      # Pricing::TaxRate refuses anything else, so a bad row would block every new document.
      t.check_constraint "percent > 0 AND percent <= 100", name: "tax_rates_percent_range"
    end
    add_index :tax_rates, :uid, unique: true
    add_index :tax_rates, "business_id, lower(name)", unique: true, where: "archived_at IS NULL",
              name: "index_tax_rates_unique_active_name"
  end
end
