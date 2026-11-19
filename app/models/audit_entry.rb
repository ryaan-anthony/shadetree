# The operator audit log (OPS-01): who did what to which business or user, why, and from where.
# Append-only: the app never updates or deletes an entry, and the database refuses to.
#
#   AuditEntry.record!(operator: current_user, action: "business.suspended", business:, reason:, request:)
class AuditEntry < ApplicationRecord
  ACTIONS = {
    "operator.granted" => "Granted operator access",
    "operator.revoked" => "Revoked operator access",
    "operator.two_factor_enabled" => "Set up two-factor",
    "console.signed_in" => "Entered the console"
  }.freeze

  belongs_to :operator_user, class_name: "User", optional: true
  belongs_to :business, optional: true
  belongs_to :target_user, class_name: "User", optional: true

  validates :action, :operator_email, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def readonly? = persisted?

  def self.record!(operator:, action:, business: nil, user: nil, reason: nil, request: nil, **data)
    create!(operator_user: operator, operator_email: operator.email, action:, business:, target_user: user, reason:, data:,
            ip_address: request&.remote_ip, user_agent: request&.user_agent.to_s.first(300).presence, request_id: request&.request_id)
  end

  def action_label = ACTIONS.fetch(action, action.humanize)

  # The database refuses to change or delete entries. schema.rb can't hold triggers, so the
  # migration adds this, and so does every schema load and test database (lib/tasks/
  # audit_log.rake, test_helper). Idempotent.
  APPEND_ONLY_SQL = <<~SQL.freeze
    CREATE OR REPLACE FUNCTION audit_entries_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'audit entries are append-only';
    END $$;
    DROP TRIGGER IF EXISTS audit_entries_no_update ON audit_entries;
    CREATE TRIGGER audit_entries_no_update BEFORE UPDATE OR DELETE ON audit_entries
      FOR EACH ROW EXECUTE FUNCTION audit_entries_append_only();
  SQL

  def self.install_append_only_trigger!
    connection.execute(APPEND_ONLY_SQL) if connection.table_exists?(:audit_entries)
  end
end
