# CLI-05: the client timeline. Each feature records what happened to a client as it happens
# (ClientEvent.record!): requests, quotes sent, opened and answered, visits booked and done,
# invoices sent and paid, payments, bounced emails and staff notes.
class CreateClientEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :client_events do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false # the page cursor and anchors (ADR 0014: ids stay internal)
      t.references :client, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.references :subject, polymorphic: true, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false

      t.index %i[business_id client_id occurred_at id], order: { occurred_at: :desc, id: :desc }, name: "index_client_events_timeline"
      t.index %i[subject_type subject_id]
      t.index %i[business_id uid], unique: true
    end
  end
end
