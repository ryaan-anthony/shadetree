# QTE-05: the client's answer to a quote (approve, decline, request changes), or staff
# recording an approval on the client's behalf. Each row is evidence: who, when, from where,
# and for an approval a snapshot of exactly what was approved.
class CreateQuoteResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :quote_responses do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :uid, null: false
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :signer_name
      t.string :email
      t.text :message
      # Client responses come through a link; staff-recorded ones have recorded_by instead.
      t.references :client_link, foreign_key: { on_delete: :nullify }
      t.references :recorded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :ip_address
      t.string :user_agent, limit: 500
      t.string :device
      t.integer :quote_version, null: false
      t.jsonb :snapshot
      t.string :snapshot_digest
      # HMAC over the whole record (who, when, from where, what): edits in the database alone
      # don't verify.
      t.string :signature, null: false
      t.datetime :created_at, null: false
      t.check_constraint "kind IN ('approved', 'declined', 'changes_requested')", name: "quote_responses_kind"
      t.check_constraint "kind <> 'approved' OR (snapshot IS NOT NULL AND snapshot_digest IS NOT NULL AND signer_name IS NOT NULL)",
                         name: "quote_responses_approval_evidence"
    end
    add_index :quote_responses, :uid, unique: true
    add_index :quote_responses, %i[business_id created_at]
    # A quote is approved at most once, whatever the race.
    add_index :quote_responses, :quote_id, unique: true, where: "kind = 'approved'", name: "index_quote_responses_one_approval"

    # The "what happens next" text a client sees after approving (settings → documents).
    add_column :businesses, :quote_approved_message, :text
  end
end
