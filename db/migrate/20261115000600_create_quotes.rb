# QTE-01: quotes and their line items. Amounts are integer cents in the quote's currency
# (copied from the business when the quote is created). Line items and tax rates are copies,
# not references, so catalog and tax-rate edits never change an existing quote.
class CreateQuotes < ActiveRecord::Migration[8.1]
  def change
    create_table :quotes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :number, null: false
      t.references :client, null: false, foreign_key: true # restrict: a client with quotes is archived, not deleted
      t.references :property, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false
      t.string :title
      t.text :message
      t.text :internal_notes
      t.text :terms
      t.date :expires_on
      # The quote's tax rates: [{ "name" => "State", "percent" => "6.25" }, …].
      t.jsonb :tax_rates, null: false, default: []
      t.boolean :prices_include_tax, null: false, default: false
      t.string :discount_kind # nil, "percent" or "amount"
      t.decimal :discount_percent, precision: 7, scale: 4
      t.bigint :discount_amount_cents
      # Totals as last saved, for lists and sorting; Quote#totals is always the source.
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :quotes, :uid, unique: true
    add_index :quotes, %i[business_id number], unique: true
    add_index :quotes, %i[business_id status created_at]
    add_check_constraint :quotes, "discount_kind IS NULL OR discount_kind IN ('percent', 'amount')", name: "quotes_discount_kind"
    add_check_constraint :quotes, "discount_percent IS NULL OR (discount_percent >= 0 AND discount_percent <= 100)", name: "quotes_discount_percent_range"
    add_check_constraint :quotes, "discount_amount_cents IS NULL OR discount_amount_cents >= 0", name: "quotes_discount_amount_nonnegative"

    create_table :quote_line_items do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.references :catalog_item, foreign_key: { on_delete: :nullify }
      # A key made in the browser, so autosaves update the same row instead of adding it again.
      t.string :key, null: false
      t.integer :position, null: false, default: 0
      t.string :name, null: false, default: ""
      t.text :description
      t.decimal :quantity, precision: 12, scale: 4, null: false, default: 1
      t.string :unit
      t.bigint :unit_price_cents, null: false, default: 0
      t.boolean :taxable, null: false, default: true
      t.string :discount_kind
      t.decimal :discount_percent, precision: 7, scale: 4
      t.bigint :discount_amount_cents
      t.timestamps
    end
    add_index :quote_line_items, %i[quote_id key], unique: true
    add_index :quote_line_items, %i[quote_id position]
    add_check_constraint :quote_line_items, "discount_kind IS NULL OR discount_kind IN ('percent', 'amount')", name: "quote_lines_discount_kind"
    add_check_constraint :quote_line_items, "quantity >= 0", name: "quote_lines_quantity_nonnegative"
  end
end
