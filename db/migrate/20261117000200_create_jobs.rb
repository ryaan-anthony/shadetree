# JOB-01: jobs, the work a business has committed to, made from an approved quote or from
# scratch. Line items are the job's own copy (editable on site); the approved quote keeps
# what the client agreed to, and the invoice will use the job's items. Like quotes, the
# *_cents totals are a cache for lists, refreshed on every save.
class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :auto_create_jobs, :boolean, null: false, default: true

    create_table :jobs do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :uid, null: false
      t.string :number, null: false
      t.references :client, null: false, foreign_key: true
      t.references :property, foreign_key: { on_delete: :nullify }
      t.references :quote, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title, null: false
      t.text :instructions
      t.text :internal_notes
      t.string :status, null: false, default: "unscheduled"
      t.string :currency, null: false
      t.jsonb :tax_rates, null: false, default: []
      t.boolean :prices_include_tax, null: false, default: false
      t.string :discount_kind
      t.decimal :discount_percent, precision: 7, scale: 4
      t.bigint :discount_amount_cents
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.datetime :completed_at
      t.references :completed_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :cancelled_at
      t.references :cancelled_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.string :cancel_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.check_constraint "status IN ('unscheduled', 'scheduled', 'in_progress', 'completed', 'cancelled')", name: "jobs_status"
      t.check_constraint "discount_kind IS NULL OR discount_kind IN ('percent', 'amount')", name: "jobs_discount_kind"
    end
    add_index :jobs, :uid, unique: true
    add_index :jobs, %i[business_id number], unique: true
    add_index :jobs, %i[business_id status created_at]

    create_table :job_line_items do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :job, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :catalog_item, foreign_key: { on_delete: :nullify }
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
      t.check_constraint "discount_kind IS NULL OR discount_kind IN ('percent', 'amount')", name: "job_lines_discount_kind"
    end
    add_index :job_line_items, %i[job_id position]
  end
end
