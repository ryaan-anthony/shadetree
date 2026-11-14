# PLT-12: secure links clients use instead of accounts. One link opens one document.
class CreateClientLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :client_links do |t|
      t.references :business, null: false, foreign_key: true
      t.string :uid, null: false
      t.references :linkable, polymorphic: true, null: false
      # The token is never stored. `secret` (random) plus the app's secret_key_base derive it;
      # `token_digest` (SHA-256 of the token) is what lookups match on.
      t.string :secret, null: false
      t.string :token_digest, null: false
      t.string :actions, array: true, null: false, default: []
      t.datetime :expires_at
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users }
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :first_viewed_at
      t.datetime :last_viewed_at
      t.integer :views_count, null: false, default: 0
      t.datetime :fresh_link_requested_at
      t.timestamps
    end
    add_index :client_links, :uid, unique: true
    add_index :client_links, :token_digest, unique: true

    create_table :client_link_events do |t|
      t.references :business, null: false, foreign_key: true
      t.references :client_link, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :device
      t.datetime :occurred_at, null: false
    end
    # One-time actions (approve, pay) can happen once per link, which also stops replays.
    add_index :client_link_events, [ :client_link_id, :kind ], unique: true,
              where: "kind NOT IN ('view', 'fresh_link_requested')", name: "index_client_link_events_once"
  end
end
