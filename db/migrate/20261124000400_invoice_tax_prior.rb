# PAY-08 (owner, 2026-11-24): a progress invoice's tax is worked out on the cumulative base, so the
# tax of all progress invoices and the final is the whole job's, rounded once. This is what the
# invoices that went out before it had billed and charged, per tax rate.
class InvoiceTaxPrior < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :tax_prior, :jsonb, null: false, default: []
  end
end
