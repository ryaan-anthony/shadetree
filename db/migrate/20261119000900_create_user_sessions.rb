# ACC-06: each signed-in browser is a session the person can see ("Chrome on Mac, last active
# 5 minutes ago") and sign out. The browser holds the id and a secret in its session; only a
# digest of the secret is stored. Signed-out sessions are kept as revoked until they're old.
class CreateUserSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :secret_digest, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_active_at, null: false
      t.datetime :revoked_at
      t.timestamps

      t.index %i[user_id revoked_at last_active_at]
    end
  end
end
