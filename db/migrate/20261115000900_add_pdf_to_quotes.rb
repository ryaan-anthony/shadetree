# QTE-02: the quote's stored PDF and the digest of the HTML it was made from (HasPdf).
class AddPdfToQuotes < ActiveRecord::Migration[8.1]
  def change
    add_reference :quotes, :pdf_blob, foreign_key: { to_table: :active_storage_blobs, on_delete: :nullify }, index: false
    add_column :quotes, :pdf_digest, :string
  end
end
