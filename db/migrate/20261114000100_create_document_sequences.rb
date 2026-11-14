# Per-business counters behind document numbers (Q-0001, INV-0001). See DocumentNumber.
class CreateDocumentSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :document_sequences do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.bigint :last_value, null: false, default: 0
      t.timestamps
    end
    add_index :document_sequences, [ :business_id, :kind ], unique: true
  end
end
