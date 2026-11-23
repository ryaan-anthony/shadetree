# PAY-08: progress billing and discount shares.
#
# invoices.kind says what an invoice is: "work" bills work (final bills, PAY-06), "progress" bills
# part of it before it's done (its lines aren't final). PAY-07 adds deposit and take_back.
#
# A fixed quote discount is shared across the quote's work invoices, and a quote line's fixed
# discount across that line's bills: each share is kept in its own column, apart from any discount
# staff type, so an edit never skews later shares.
#
# invoice_credits are what an invoice takes off: progress billed earlier and over-billing (both
# before tax, at the tax rates the progress was charged at), and later deposits and take-backs
# (after tax, PAY-07). Each points at the progress line (and its invoice) it credits.
class ProgressBillingAndDiscountShares < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :kind, :string, null: false, default: "work"
    add_check_constraint :invoices, "kind IN ('work', 'progress')", name: "invoices_kind"
    add_column :invoices, :quote_discount_share_cents, :bigint, null: false, default: 0
    add_check_constraint :invoices, "quote_discount_share_cents >= 0", name: "invoices_quote_discount_share_nonnegative"
    add_column :invoice_line_items, :discount_share_cents, :bigint, null: false, default: 0
    add_check_constraint :invoice_line_items, "discount_share_cents >= 0", name: "invoice_line_items_discount_share_nonnegative"

    create_table :invoice_credits do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :invoice, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.references :source_invoice, null: false, foreign_key: { to_table: :invoices }
      t.references :source_line_item, foreign_key: { to_table: :invoice_line_items, on_delete: :nullify } # drafts rework; void ones keep theirs
      t.bigint :amount_cents, null: false
      t.integer :sign, null: false, default: -1
      t.jsonb :tax_rates, null: false, default: []
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :invoice_credits, "kind IN ('progress', 'over_billed')", name: "invoice_credits_kind"
    add_check_constraint :invoice_credits, "amount_cents > 0", name: "invoice_credits_amount_positive"
    add_check_constraint :invoice_credits, "sign IN (-1, 1)", name: "invoice_credits_sign"
  end
end
