# JOB-09: a quote's work splits across jobs. Each job's share of a quote line is a claim
# (job_claims), the one source of which job holds what; quote_line_items.claimed_quantity is the
# sum of the line's live claims, kept by atomic updates and checked by the database so two people
# can't both take the same trees. QTE-09's migration extends the check with its Not going ahead
# quantity.
#
# A claim is live while its job isn't cancelled, or, with no job (PAY-06's direct billing),
# while its invoice line's invoice isn't void; deleting that line must release the claim first.
#
# work_entries is the append-only log of what was done on a job line, per person and visit; a
# line's done quantity is the sum. jobs.picker_token makes a resubmitted picker open the job it
# made, so jobs.quote_id is no longer unique.
#
# Existing jobs claim their quote's lines, and quotes billed straight from the quote with no job
# claim what their invoices bill (backfill below). Down refuses once a quote has two
# jobs, since the one-job index can't come back.
class JobsAsPartsOfAQuote < ActiveRecord::Migration[8.1]
  def up
    add_column :quote_line_items, :claimed_quantity, :decimal, precision: 12, scale: 4, default: 0, null: false

    create_table :job_claims do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :job, foreign_key: { on_delete: :cascade }, index: false # as its lines go with it
      t.references :quote_line_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :job_line_item, foreign_key: { on_delete: :nullify }, index: { unique: true, where: "job_line_item_id IS NOT NULL" }
      t.references :invoice_line_item, foreign_key: true, index: { unique: true, where: "invoice_line_item_id IS NOT NULL" }
      t.decimal :quantity, precision: 12, scale: 4, null: false
      t.decimal :extra_quantity, precision: 12, scale: 4, null: false, default: 0 # taken at completion for more done than booked
      t.timestamps
    end
    add_index :job_claims, %i[job_id quote_line_item_id], unique: true, where: "job_id IS NOT NULL"
    add_index :job_claims, :business_id
    add_check_constraint :job_claims, "quantity >= 0", name: "job_claims_quantity_nonnegative"
    add_check_constraint :job_claims, "job_id IS NOT NULL OR invoice_line_item_id IS NOT NULL", name: "job_claims_job_or_invoice"

    create_table :work_entries do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :job, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :job_line_item, foreign_key: { on_delete: :nullify } # a removed line keeps its log
      t.string :item_name, null: false # the line's name when logged
      t.references :visit, foreign_key: { on_delete: :nullify }
      t.references :user, null: false, foreign_key: true # whose work it is
      t.references :recorded_by, foreign_key: { to_table: :users } # who typed it (the office corrects anyone's)
      t.decimal :quantity, precision: 12, scale: 4, null: false # a change: a correction is another entry
      t.string :source, null: false, default: "logged"
      t.datetime :created_at, null: false
    end
    add_index :work_entries, %i[business_id job_id]
    add_check_constraint :work_entries, "source IN ('logged', 'time')", name: "work_entries_source"

    add_column :job_line_items, :price_pending, :boolean, default: false, null: false # added on site, unpriced
    add_column :job_line_items, :booked_quantity, :decimal, precision: 12, scale: 4 # what it booked, while completed
    add_column :jobs, :picker_token, :string
    remove_index :jobs, :quote_id
    add_index :jobs, :quote_id
    add_index :jobs, %i[quote_id picker_token], unique: true, where: "picker_token IS NOT NULL"

    claim_existing_jobs
    claim_direct_billing
    add_check_constraint :quote_line_items, "claimed_quantity >= 0 AND claimed_quantity <= quantity", name: "quote_lines_claims_within_quantity"
  end

  def down
    if select_value("SELECT 1 FROM jobs WHERE quote_id IS NOT NULL GROUP BY quote_id HAVING COUNT(*) > 1 LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "A quote has more than one job; the one-job-per-quote index can't be restored."
    end

    remove_check_constraint :quote_line_items, name: "quote_lines_claims_within_quantity"
    remove_index :jobs, %i[quote_id picker_token]
    remove_index :jobs, :quote_id
    add_index :jobs, :quote_id, unique: true
    remove_column :jobs, :picker_token
    remove_column :job_line_items, :booked_quantity
    remove_column :job_line_items, :price_pending
    drop_table :work_entries
    drop_table :job_claims
    remove_column :quote_line_items, :claimed_quantity
  end

  # Every job made from a quote claims the quote's lines, clamped to the line's quantity. A quote
  # line is matched to the job line copied from it: the first one not yet matched, in position
  # order, with the same catalog item, name and unit price. A line with no match (removed or
  # renamed on the job) is claimed in full without a job line, since the quote's one job took
  # everything. Cancelled jobs keep their claims too, but they aren't live. No total changes.
  def claim_existing_jobs
    jobs = select_rows("SELECT id, business_id, quote_id, status FROM jobs WHERE quote_id IS NOT NULL ORDER BY id")
    jobs.each do |job_id, business_id, quote_id, status|
      job_lines = select_rows("SELECT id, catalog_item_id, name, unit_price_cents, quantity FROM job_line_items WHERE job_id = #{job_id.to_i} ORDER BY position, id")
      select_rows("SELECT id, catalog_item_id, name, unit_price_cents, quantity FROM quote_line_items WHERE quote_id = #{quote_id.to_i} ORDER BY position, id").each do |line_id, item, name, price, quantity|
        match = job_lines.find { |_, job_item, job_name, job_price| job_item == item && job_name == name && job_price.to_i == price.to_i }
        job_lines.delete(match)
        claimed = match ? [ match[4].to_d, quantity.to_d ].min : quantity.to_d
        execute <<~SQL.squish
          INSERT INTO job_claims (business_id, job_id, quote_line_item_id, job_line_item_id, quantity, created_at, updated_at)
          VALUES (#{business_id.to_i}, #{job_id.to_i}, #{line_id.to_i}, #{match ? match[0].to_i : "NULL"}, #{claimed.to_s("F")}, now(), now())
        SQL
        execute "UPDATE quote_line_items SET claimed_quantity = claimed_quantity + #{claimed.to_s("F")} WHERE id = #{line_id.to_i}" unless status == "cancelled"
      end
    end
  end

  # A quote billed directly (its invoice from the quote, with no job, and no job that isn't
  # cancelled) claims what each invoice that isn't void bills, oldest invoice first: invoice lines
  # are matched to quote lines as job lines are, clamped to what's left. Those claims have no job
  # and point at the invoice line, so the work isn't offered again as to do.
  def claim_direct_billing
    invoices = select_rows(<<~SQL.squish)
      SELECT invoices.id, invoices.business_id, invoices.quote_id FROM invoices
      WHERE invoices.quote_id IS NOT NULL AND invoices.job_id IS NULL AND invoices.status <> 'void'
        AND NOT EXISTS (SELECT 1 FROM jobs WHERE jobs.quote_id = invoices.quote_id AND jobs.status <> 'cancelled')
      ORDER BY invoices.id
    SQL
    invoices.each do |invoice_id, business_id, quote_id|
      billed = select_rows("SELECT id, catalog_item_id, name, unit_price_cents, quantity FROM invoice_line_items WHERE invoice_id = #{invoice_id.to_i} ORDER BY position, id")
      select_rows("SELECT id, catalog_item_id, name, unit_price_cents, quantity, claimed_quantity FROM quote_line_items WHERE quote_id = #{quote_id.to_i} ORDER BY position, id").each do |line_id, item, name, price, quantity, claimed|
        match = billed.find { |_, line_item, line_name, line_price| line_item == item && line_name == name && line_price.to_i == price.to_i }
        next unless match

        billed.delete(match)
        claim = [ match[4].to_d, quantity.to_d - claimed.to_d ].min
        next unless claim.positive?

        execute <<~SQL.squish
          INSERT INTO job_claims (business_id, job_id, quote_line_item_id, invoice_line_item_id, quantity, created_at, updated_at)
          VALUES (#{business_id.to_i}, NULL, #{line_id.to_i}, #{match[0].to_i}, #{claim.to_s("F")}, now(), now())
        SQL
        execute "UPDATE quote_line_items SET claimed_quantity = claimed_quantity + #{claim.to_s("F")} WHERE id = #{line_id.to_i}"
      end
    end
  end
end
