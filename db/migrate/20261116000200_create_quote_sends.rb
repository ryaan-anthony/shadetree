# QTE-04: sending a quote. Each send (email or copied link) is recorded; the first one marks
# the quote sent and records a billable usage event (BIL-02 counts them).
class CreateQuoteSends < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :sent_at, :datetime
    add_reference :quotes, :sent_by, foreign_key: { to_table: :users, on_delete: :nullify }

    create_table :quote_sends do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :channel, null: false
      t.string :recipient
      t.string :cc
      t.references :email_message, foreign_key: { on_delete: :nullify }
      t.timestamps
      t.check_constraint "channel IN ('email', 'link')", name: "quote_sends_channel"
    end
    add_index :quote_sends, %i[business_id quote_id]

    # Billable events, counted per business per period by BIL-02. One per kind per subject:
    # the unique index makes recording idempotent under retries and concurrent requests.
    create_table :usage_events do |t|
      t.references :business, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.references :subject, polymorphic: true, null: false, index: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :usage_events, %i[kind subject_type subject_id], unique: true
    add_index :usage_events, %i[business_id kind occurred_at]
  end
end
