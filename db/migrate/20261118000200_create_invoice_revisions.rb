# PAY-01: a sent invoice changes only by revision. Each revision keeps what the client was sent
# (lines, totals, dates, its status and the PDF they got), and the invoice counts its revisions like a quote does (QTE-06).
class CreateInvoiceRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :revision, :integer, null: false, default: 1
    add_foreign_key :invoices, :active_storage_blobs, column: :pdf_blob_id, on_delete: :nullify

    create_table :invoice_revisions do |t|
      t.references :business, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true, index: false
      t.integer :number, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.string :status, null: false
      t.datetime :sent_at
      # The PDF the client got (PAY-02 stores it), kept when the invoice's own is replaced.
      t.references :pdf_blob, foreign_key: { to_table: :active_storage_blobs, on_delete: :nullify }
      t.references :revised_by, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false

      t.index %i[invoice_id number], unique: true
    end
  end
end
