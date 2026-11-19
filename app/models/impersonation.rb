# OPS-03: an operator viewing the app as one member of one business. Kept in the operator's own
# signed-in session data (so signing out ends it), read-only unless the operator explicitly
# allows changes, and ended after IDLE_TIMEOUT without a request or MAX_LENGTH in all.
#
#   impersonation = Impersonation.load(session_data, operator_user)  # nil when there's none, or it's no longer valid
#   impersonation.user          # the member being viewed as
#   impersonation.read_only?
class Impersonation
  KEY = "impersonation".freeze
  IDLE_TIMEOUT = 15.minutes # the same as the console's (Ops::BaseController)
  MAX_LENGTH = 1.hour
  MODES = %w[read_only write].freeze

  attr_reader :data, :operator, :membership

  def self.start!(session_data, operator:, membership:)
    now = Time.current.to_i
    session_data[KEY] = { "id" => SecureRandom.hex(8), "operator_id" => operator.id, "membership_id" => membership.id,
                          "business_id" => membership.business_id, "mode" => "read_only", "started_at" => now, "seen_at" => now }
    new(session_data[KEY], operator, membership)
  end

  def self.present?(session_data) = session_data[KEY].is_a?(Hash)

  # The impersonation in this session, or nil. A stale one (timed out, a grant revoked, a
  # membership ended) is returned with ended_because set, for the caller to record and clear.
  def self.load(session_data, operator_user)
    data = session_data[KEY]
    return unless data.is_a?(Hash)

    membership = BusinessUser.includes(:user, :business).find_by(id: data["membership_id"], business_id: data["business_id"])
    new(data, operator_user, membership)
  end

  def initialize(data, operator, membership)
    @data = data
    @operator = operator
    @membership = membership
  end

  def id = data["id"]
  def user = membership.user
  def business = membership.business
  def mode = data["mode"]
  def read_only? = mode != "write"
  def started_at = Time.zone.at(data["started_at"])
  def minutes = ((Time.current - started_at) / 60).round

  # Why this session can't go on, or nil if it can.
  def ended_because
    return "timed_out" if Time.zone.at(data["seen_at"].to_i) < IDLE_TIMEOUT.ago || started_at < MAX_LENGTH.ago
    return "access_changed" unless operator && data["operator_id"] == operator.id && Operator.for(operator)
    return "access_changed" unless membership&.active? && !membership.user.deleted?

    nil
  end

  def touch! = data["seen_at"] = Time.current.to_i

  def mode=(value)
    data["mode"] = MODES.include?(value) ? value : "read_only"
  end

  def self.clear!(session_data) = session_data.delete(KEY)

  # Who may be viewed as: an active member who isn't the operator or another operator.
  def self.refusal_for(membership, operator:)
    if membership.nil? || !membership.active? || membership.user.deleted? then "Pick an active member of this business."
    elsif membership.user_id == operator.id then "You can't view the app as yourself."
    elsif Operator.for(membership.user) then "Operators can't be viewed as."
    end
  end
end
