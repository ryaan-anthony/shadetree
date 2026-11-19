# The operator audit log (OPS-01): who did what to which business or user, why, and from where.
# Append-only: the app never updates or deletes an entry, and the database refuses to.
#
#   AuditEntry.record!(operator: current_user, action: "business.suspended", business:, reason:, request:)
class AuditEntry < ApplicationRecord
  ACTIONS = {
    "operator.granted" => "Granted operator access",
    "operator.revoked" => "Revoked operator access",
    "operator.two_factor_enabled" => "Set up two-factor",
    "operator.two_factor_reset" => "Reset two-factor",
    "operator.locked_out" => "Locked out after too many wrong codes",
    "operator.recovery_code_used" => "Used a recovery code",
    "operator.recovery_codes_regenerated" => "Made new recovery codes",
    "console.signed_in" => "Entered the console",
    "business.viewed" => "Opened a business",
    "business.note_added" => "Added a note",
    "business.note_edited" => "Edited a note",
    "business.note_deleted" => "Deleted a note"
  }.freeze

  belongs_to :operator_user, class_name: "User", optional: true
  belongs_to :business, optional: true
  belongs_to :target_user, class_name: "User", optional: true

  validates :action, :operator_email, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def readonly? = persisted?

  # operator: the user acting, or nil with operator_email naming who did (e.g. "command line").
  def self.record!(operator:, action:, business: nil, user: nil, reason: nil, request: nil, operator_email: operator&.email, **data)
    create!(operator_user: operator, operator_email:, action:, business:, target_user: user, reason:, data:,
            ip_address: request&.remote_ip, user_agent: request&.user_agent.to_s.first(300).presence, request_id: request&.request_id)
  end

  def action_label = ACTIONS.fetch(action, action.humanize)

  # The database refuses to change, delete or truncate entries. schema.rb can't hold triggers,
  # so the migration adds this, and so does every schema load, db:prepare and test database
  # (lib/tasks/audit_log.rake, test_helper). Idempotent.
  APPEND_ONLY_SQL = <<~SQL.freeze
    CREATE OR REPLACE FUNCTION audit_entries_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'audit entries are append-only';
    END $$;
    DROP TRIGGER IF EXISTS audit_entries_no_update ON audit_entries;
    CREATE TRIGGER audit_entries_no_update BEFORE UPDATE OR DELETE ON audit_entries
      FOR EACH ROW EXECUTE FUNCTION audit_entries_append_only();
    DROP TRIGGER IF EXISTS audit_entries_no_truncate ON audit_entries;
    CREATE TRIGGER audit_entries_no_truncate BEFORE TRUNCATE ON audit_entries
      FOR EACH STATEMENT EXECUTE FUNCTION audit_entries_append_only();
  SQL

  def self.install_append_only_trigger!(conn = connection)
    conn.execute(APPEND_ONLY_SQL) if conn.table_exists?(:audit_entries)
  end

  # Both triggers in place? The console's home warns if not (a database built some way that
  # skipped lib/tasks/audit_log.rake).
  def self.append_only? = connection.select_value(<<~SQL).to_i == 2
    SELECT count(*) FROM pg_trigger WHERE tgrelid = 'audit_entries'::regclass
      AND tgname IN ('audit_entries_no_update', 'audit_entries_no_truncate') AND NOT tgisinternal
  SQL
end
