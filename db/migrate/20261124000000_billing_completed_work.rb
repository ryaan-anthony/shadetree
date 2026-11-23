# PAY-06: an invoice bills completed work, and nothing is billed twice. Each invoice line says
# which job line or quote line it bills and whether it's that line's final bill (progress amounts,
# PAY-08, aren't). The database refuses a second final bill for a line on an invoice that isn't
# void: the lines carry their invoice's status (kept by a cascading foreign key, so voiding frees
# them at once) and two partial unique indexes look at it. Lines are inserted only on drafts: the
# status starts as draft, and the foreign key refuses a draft line on any other invoice.
#
# invoice_jobs lists every job an invoice bills (a quote's invoice can bill several); invoices.job_id
# keeps one of them. A line can carry its own tax rates, its job's, when an invoice's jobs differ.
#
# Existing invoices that aren't void are linked to the lines they came from (backfill below);
# where one line was billed more than once, the earliest invoice is its final bill.
class BillingCompletedWork < ActiveRecord::Migration[8.1]
  def up
    add_reference :invoice_line_items, :job_line_item, foreign_key: { on_delete: :nullify }
    add_reference :invoice_line_items, :quote_line_item, foreign_key: { on_delete: :nullify }
    add_column :invoice_line_items, :final, :boolean, null: false, default: false
    add_column :invoice_line_items, :tax_rates, :jsonb # its job's rates; nil: the invoice's
    add_column :invoice_line_items, :invoice_status, :string, null: false, default: "draft"
    execute "UPDATE invoice_line_items SET invoice_status = invoices.status FROM invoices WHERE invoices.id = invoice_line_items.invoice_id"
    add_index :invoices, %i[id status], unique: true
    add_foreign_key :invoice_line_items, :invoices, column: %i[invoice_id invoice_status], primary_key: %i[id status],
                                                    on_update: :cascade, on_delete: :cascade, name: "fk_invoice_line_items_invoice_status"

    create_table :invoice_jobs do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :invoice, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :job, null: false, foreign_key: true
      t.timestamps
    end
    add_index :invoice_jobs, %i[invoice_id job_id], unique: true

    link_existing_invoices
    add_index :invoice_line_items, :job_line_item_id, unique: true, where: "final AND invoice_status <> 'void'", name: "index_invoice_lines_one_final_bill_per_job_line"
    add_index :invoice_line_items, :quote_line_item_id, unique: true, where: "final AND invoice_status <> 'void' AND job_line_item_id IS NULL",
                                                        name: "index_invoice_lines_one_final_bill_per_quote_line"
  end

  def down
    drop_table :invoice_jobs
    remove_foreign_key :invoice_line_items, name: "fk_invoice_line_items_invoice_status"
    remove_index :invoices, %i[id status]
    remove_index :invoice_line_items, name: "index_invoice_lines_one_final_bill_per_job_line"
    remove_index :invoice_line_items, name: "index_invoice_lines_one_final_bill_per_quote_line"
    remove_columns :invoice_line_items, :invoice_status, :tax_rates, :final
    remove_reference :invoice_line_items, :quote_line_item
    remove_reference :invoice_line_items, :job_line_item
  end

  # Every invoice with a job lists it in invoice_jobs. Then each invoice that isn't void, oldest
  # first, links its lines: one from a job (or from a quote with a job that isn't cancelled) to the
  # job's lines, one billed straight from the quote to the quote's lines. A line is matched to the
  # first unmatched line, in position order, with the same catalog item, name and unit price, then
  # by catalog item and name alone. A job line keeps its quote line (its claim). The first invoice
  # to bill a line is its final bill; later ones are progress. Nothing is credited after the fact.
  def link_existing_invoices
    execute <<~SQL.squish
      INSERT INTO invoice_jobs (business_id, invoice_id, job_id, created_at, updated_at)
      SELECT business_id, id, job_id, now(), now() FROM invoices WHERE job_id IS NOT NULL
    SQL
    billed = Set.new
    invoices = select_rows("SELECT id, business_id, job_id, quote_id FROM invoices WHERE status <> 'void' AND (job_id IS NOT NULL OR quote_id IS NOT NULL) ORDER BY created_at, id")
    invoices.each do |invoice_id, business_id, job_id, quote_id|
      job_id ||= select_value("SELECT id FROM jobs WHERE quote_id = #{quote_id.to_i} AND status <> 'cancelled' ORDER BY id LIMIT 1")
      targets = job_id ? job_lines(job_id) : quote_lines(quote_id)
      lines = select_rows("SELECT id, catalog_item_id, name, unit_price_cents FROM invoice_line_items WHERE invoice_id = #{invoice_id.to_i} ORDER BY position, id")
      matched = match(lines, targets)
      matched.each do |line_id, (target_id, quote_line_id)|
        key = job_id ? [ :job, target_id ] : [ :quote, target_id ]
        final = billed.add?(key) ? "TRUE" : "FALSE"
        execute <<~SQL.squish
          UPDATE invoice_line_items SET job_line_item_id = #{job_id ? target_id.to_i : "NULL"}, quote_line_item_id = #{quote_line_id ? quote_line_id.to_i : "NULL"},
                 final = #{final} WHERE id = #{line_id.to_i}
        SQL
      end
      next unless job_id && matched.any?

      execute "UPDATE invoices SET job_id = #{job_id.to_i} WHERE id = #{invoice_id.to_i} AND job_id IS NULL"
      execute <<~SQL.squish
        INSERT INTO invoice_jobs (business_id, invoice_id, job_id, created_at, updated_at)
        VALUES (#{business_id.to_i}, #{invoice_id.to_i}, #{job_id.to_i}, now(), now()) ON CONFLICT DO NOTHING
      SQL
    end
  end

  # [id, catalog item, name, price, quote line id]
  def job_lines(job_id)
    select_rows(<<~SQL.squish)
      SELECT job_line_items.id, catalog_item_id, name, unit_price_cents, job_claims.quote_line_item_id FROM job_line_items
      LEFT JOIN job_claims ON job_claims.job_line_item_id = job_line_items.id
      WHERE job_line_items.job_id = #{job_id.to_i} ORDER BY position, job_line_items.id
    SQL
  end

  def quote_lines(quote_id)
    select_rows("SELECT id, catalog_item_id, name, unit_price_cents, id FROM quote_line_items WHERE quote_id = #{quote_id.to_i} ORDER BY position, id")
  end

  # { invoice line id => [target id, quote line id] }: exact matches first, then by item and name.
  def match(lines, targets)
    free = targets.dup
    matched = {}
    [ ->(line, target) { line[1..3].map(&:to_s) == target[1..3].map(&:to_s) }, ->(line, target) { line[1..2].map(&:to_s) == target[1..2].map(&:to_s) } ].each do |same|
      lines.each do |line|
        next if matched.key?(line[0]) || !(target = free.find { same.(line, _1) })

        free.delete(target)
        matched[line[0]] = [ target[0], target[4] ]
      end
    end
    matched.sort_by { |line_id, _| lines.index { _1[0] == line_id } }.to_h
  end
end
