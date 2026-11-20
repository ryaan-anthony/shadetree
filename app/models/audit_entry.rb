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
    "business.note_deleted" => "Deleted a note",
    "impersonation.started" => "Started viewing as a member",
    "impersonation.changes_allowed" => "Allowed changes while viewing as a member",
    "impersonation.read_only" => "Went back to read-only",
    "impersonation.change" => "Made a change while viewing as a member",
    "impersonation.ended" => "Stopped viewing as a member",
    "business.suspended" => "Suspended a business",
    "business.reactivated" => "Reactivated a business",
    "business.deletion_scheduled" => "Scheduled a business for deletion",
    "business.deletion_expedited" => "Deleted a business without waiting",
    "business.deletion_cancelled" => "Cancelled a business's deletion",
    "business.deleted" => "Deleted a business and all its data",
    "business.plan_overrides_changed" => "Changed a business's limits or features",
    "plan.updated" => "Edited a plan",
    "preset.updated" => "Edited an industry preset",
    "feature_flag.changed" => "Changed a release flag",
    "user.confirmation_resent" => "Resent a confirmation email",
    "user.password_reset_sent" => "Sent a password reset",
    "user.unlocked" => "Unlocked an account",
    "contact_message.deleted" => "Deleted a contact message",
    "contact_message.erased" => "Deleted everything from a contact-form sender",
    "ticket.viewed" => "Opened a support ticket",
    "ticket.assigned" => "Assigned a support ticket",
    "ticket.replied" => "Replied to a support ticket",
    "ticket.noted" => "Added a note to a support ticket",
    "ticket.status_changed" => "Changed a support ticket's status",
    "ticket.auto_resolved" => "Support ticket resolved automatically"
  }.freeze

  belongs_to :operator_user, class_name: "User", optional: true
  belongs_to :business, optional: true
  belongs_to :target_user, class_name: "User", optional: true

  validates :action, :operator_email, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def readonly? = persisted?

  # operator: the user acting, or nil with operator_email naming who did (e.g. "command line").
  def self.record!(operator:, action:, business: nil, user: nil, reason: nil, request: nil, operator_email: operator&.email, **data)
    # The business's name and id are kept on the entry too (OPS-04), so it still reads, and can be
    # filtered, after the business is deleted.
    data = data.merge(business_name: business.name, business_uid: business.uid) if business
    create!(operator_user: operator, operator_email:, action:, business:, target_user: user, reason:, data:,
            ip_address: request&.remote_ip, user_agent: request&.user_agent.to_s.first(300).presence, request_id: request&.request_id)
  end

  def action_label = ACTIONS.fetch(action, action.humanize)

  # OPS-03: the times Shadetree support viewed a business's app as one of its members, for its
  # Owners: when, as whom, whether changes were allowed, and how long. Nothing about which operator.
  SupportVisit = Data.define(:started_at, :member_name, :changes_allowed, :changes, :minutes)

  def self.support_visits(business, limit: 10)
    starts = where(business:, action: "impersonation.started").newest_first.limit(limit).includes(:target_user).to_a
    sessions = starts.map { _1.data["session"] }
    related = where(business:, action: %w[impersonation.changes_allowed impersonation.change impersonation.ended])
              .where("data->>'session' IN (?)", sessions.presence || [ "" ]).group_by { _1.data["session"] }
    starts.map do |start|
      later = related.fetch(start.data["session"], [])
      ended = later.find { _1.action == "impersonation.ended" }
      SupportVisit.new(started_at: start.created_at, member_name: start.target_user&.full_name || "a former member",
                       changes_allowed: later.any? { _1.action == "impersonation.changes_allowed" },
                       changes: later.count { _1.action == "impersonation.change" }, minutes: ended&.data&.dig("minutes"))
    end
  end
  # The business's name, from the entry if the business has since been deleted.
  def business_label = business&.name || (data["business_name"] && "#{data["business_name"]} (deleted)")

  # A short, non-personal detail shown under the label (what the entry's data records).
  def detail
    case action
    when "contact_message.deleted" then "Message #{data["message"]}#{" (spam)" if data["spam"]}"
    when "contact_message.erased" then ActionController::Base.helpers.pluralize(data["count"].to_i, "message")
    end
  end

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
