# PAY-01: a sent invoice changes only by revision. Each revision keeps what the client was sent
# (lines, totals, dates), and the invoice counts its revisions like a quote does (QTE-06).
class CreateInvoiceRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :revision, :integer, null: false, default: 1

    create_table :invoice_revisions do |t|
      t.references :business, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true, index: false
      t.integer :number, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.references :revised_by, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false

      t.index %i[invoice_id number], unique: true
    end
  end
end
