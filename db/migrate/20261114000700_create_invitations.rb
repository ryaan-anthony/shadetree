# ACC-03: email invitations to join a business, and when each member was last active.
class CreateInvitations < ActiveRecord::Migration[8.1]
  def up
    create_table :invitations do |t|
      t.references :business, null: false, foreign_key: true
      t.string :uid, null: false
      t.string :email, null: false
      t.string :role, null: false
      # Token = HMAC(secret_key_base, secret); only its digest is matched (as for client links).
      t.string :secret, null: false
      t.string :token_digest, null: false
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :last_sent_at
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :invitations, :uid, unique: true
    add_index :invitations, :token_digest, unique: true
    add_index :invitations, "business_id, lower(email)", unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_invitations_one_pending_per_email"

    add_column :business_users, :last_active_at, :datetime
    add_column :business_users, :deactivated_at, :datetime
    # Opaque ids for member URLs on the team page (ADR 0014).
    add_column :business_users, :uid, :string
    execute "UPDATE business_users SET uid = substr(md5(random()::text || id::text), 1, 12) WHERE uid IS NULL"
    change_column_null :business_users, :uid, false
    add_index :business_users, :uid, unique: true
  end

  def down
    remove_column :business_users, :uid
    remove_column :business_users, :deactivated_at
    remove_column :business_users, :last_active_at
    drop_table :invitations
  end
end
