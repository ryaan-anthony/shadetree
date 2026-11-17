# QTE-06 (part 2): revisions. Revising a sent quote keeps what the client was sent as a
# numbered revision (a snapshot and its PDF) and reopens the quote as a draft of the next
# revision; sending it again is what the client sees next.
class CreateQuoteRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :revision, :integer, null: false, default: 1
    add_column :quote_sends, :revision, :integer, null: false, default: 1
    add_column :quote_responses, :revision, :integer, null: false, default: 1

    create_table :quote_revisions do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }, index: false # [quote_id, number] below
      t.integer :number, null: false
      # What the client was sent, as QuoteResponse.snapshot_of records it, and its PDF.
      t.jsonb :snapshot, null: false
      t.references :pdf_blob, foreign_key: { to_table: :active_storage_blobs, on_delete: :nullify }
      t.string :status, null: false # where it stood when superseded: sent, changes_requested, declined, expired
      t.datetime :sent_at
      t.references :revised_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
    end
    add_index :quote_revisions, %i[quote_id number], unique: true
    add_index :quote_revisions, :business_id
  end
end
