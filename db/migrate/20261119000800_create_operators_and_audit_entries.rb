# OPS-01: operator access (a grant on a user, independent of business memberships, with its own
# two-factor secret) and the append-only audit log every operator action writes to. The
# database itself refuses to change or delete audit entries (the trigger; schema loads add it
# too, lib/tasks/audit_log.rake).
class CreateOperatorsAndAuditEntries < ActiveRecord::Migration[8.1]
  def up
    create_table :operators do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :granted_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :otp_secret_ciphertext # encrypted with a key derived from secret_key_base
      t.datetime :otp_enabled_at
      t.bigint :otp_last_step # the last time step accepted, so a code can't be replayed
      t.jsonb :recovery_code_digests, null: false, default: []
      t.timestamps
    end

    create_table :audit_entries do |t|
      t.references :operator_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :operator_email, null: false # kept if the user is ever deleted
      t.string :action, null: false
      t.references :business, foreign_key: { on_delete: :nullify }
      t.references :target_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :reason
      t.jsonb :data, null: false, default: {}
      t.string :ip_address
      t.string :user_agent
      t.string :request_id
      t.datetime :created_at, null: false

      t.index :action
      t.index :created_at
    end

    execute <<~SQL
      CREATE FUNCTION audit_entries_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'audit entries are append-only';
      END $$;
      CREATE TRIGGER audit_entries_no_update BEFORE UPDATE OR DELETE ON audit_entries
        FOR EACH ROW EXECUTE FUNCTION audit_entries_append_only();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS audit_entries_no_update ON audit_entries; DROP FUNCTION IF EXISTS audit_entries_append_only();"
    drop_table :audit_entries
    drop_table :operators
  end
end
