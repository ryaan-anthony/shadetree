# CLI-06: bringing a client list over from a CSV. An import keeps the uploaded file (until it's
# finished), how its columns map to client fields, what to do with likely duplicates, and its
# progress and results; clients it created point back to it, so it can be undone for a while.
class CreateClientImports < ActiveRecord::Migration[8.1]
  def change
    create_table :client_imports do |t|
      t.references :business, null: false, foreign_key: true
      t.string :uid, null: false, index: { unique: true }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :filename, null: false
      t.string :status, null: false, default: "mapping" # mapping, queued, importing, finished, failed, undone
      t.jsonb :headers, null: false, default: []
      t.jsonb :mapping, null: false, default: {}  # header index => field
      t.string :duplicates, null: false, default: "skip" # skip or create
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.jsonb :problems, null: false, default: [] # [{ "row" => 7, "reason" => "...", "values" => [...] }], capped
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :undone_at
      t.timestamps
    end

    add_reference :clients, :client_import, foreign_key: { on_delete: :nullify }
  end
end
