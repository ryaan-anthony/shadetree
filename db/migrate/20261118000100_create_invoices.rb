# PAY-01: invoices. They price like quotes (the same line, discount and tax columns, PLT-08)
# and carry what the client is billed: an issue date, payment terms and the due date they
# give, and what's been paid so far (PAY-04/PAY-05 add the payments). A job or an approved
# quote can have several invoices; each invoice names the one it came from.
class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :business, null: false, foreign_key: true
      t.string :uid, null: false, index: { unique: true }
      t.string :number, null: false
      t.references :client, null: false, foreign_key: true
      t.references :property, foreign_key: true
      t.references :job, foreign_key: true
      t.references :quote, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false
      t.string :title
      t.date :issued_on, null: false
      t.string :payment_terms, null: false, default: "due_on_receipt"
      t.date :due_on, null: false
      t.text :message
      t.text :terms
      t.text :internal_notes
      t.jsonb :tax_rates, null: false, default: []
      t.boolean :prices_include_tax, null: false, default: false
      t.string :discount_kind
      t.decimal :discount_percent, precision: 7, scale: 4
      t.bigint :discount_amount_cents
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :amount_paid_cents, null: false, default: 0
      t.datetime :sent_at
      t.references :sent_by, foreign_key: { to_table: :users }
      t.datetime :voided_at
      t.references :voided_by, foreign_key: { to_table: :users }
      t.string :void_reason
      t.bigint :pdf_blob_id
      t.string :pdf_digest
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[business_id number], unique: true
      t.index %i[business_id status due_on]
      t.check_constraint "status IN ('draft', 'sent', 'partially_paid', 'paid', 'void')", name: "invoices_status"
      t.check_constraint "payment_terms IN ('due_on_receipt', 'net_7', 'net_15', 'net_30', 'custom')", name: "invoices_payment_terms"
      t.check_constraint "due_on >= issued_on", name: "invoices_due_after_issue"
      t.check_constraint "amount_paid_cents >= 0", name: "invoices_amount_paid_nonnegative"
      t.check_constraint "discount_kind IS NULL OR discount_kind IN ('percent', 'amount')", name: "invoices_discount_kind"
      t.check_constraint "discount_percent IS NULL OR discount_percent BETWEEN 0 AND 100", name: "invoices_discount_percent_range"
      t.check_constraint "discount_amount_cents IS NULL OR discount_amount_cents >= 0", name: "invoices_discount_amount_nonnegative"
    end

    create_table :invoice_line_items do |t|
      t.references :business, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true, index: false
      t.references :catalog_item, foreign_key: true
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

      t.index %i[invoice_id key], unique: true
      t.index %i[invoice_id position]
      t.check_constraint "quantity >= 0", name: "invoice_lines_quantity_nonnegative"
      t.check_constraint "discount_kind IS NULL OR discount_kind IN ('percent', 'amount')", name: "invoice_lines_discount_kind"
    end

    # Status changes and other staff actions, for the invoice's history.
    create_table :invoice_events do |t|
      t.references :business, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.index %i[invoice_id occurred_at]
    end
  end
end
