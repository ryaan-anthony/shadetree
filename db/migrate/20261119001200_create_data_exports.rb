# INS-02: every export of a business's data, logged (who, what, when). A full-account export
# is built in the background into a zip kept until it expires.
class CreateDataExports < ActiveRecord::Migration[8.1]
  def change
    create_table :data_exports do |t|
      t.references :business, null: false, foreign_key: true
      t.string :uid, null: false, index: { unique: true }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :requested_by_email # kept on the log if the person is later removed
      t.string :kind, null: false # a table (clients, quotes, ...), "full", or "full_download" (someone downloaded a full export)
      t.string :status, null: false, default: "ready" # building, ready, failed, expired
      t.integer :rows_count
      t.string :failure_reason # shown on the page when a full export couldn't be made
      t.datetime :expires_at
      t.timestamps
      t.index %i[business_id created_at]
    end
  end
end
