# NTF-04: a business's automation. When a core-flow event happens (TRIGGERS), and after an
# optional delay, if its conditions still hold (CONDITIONS), it runs its actions (ACTIONS):
#
#   { trigger: "quote_sent", delay_minutes: 3 * 24 * 60, conditions: { "still_open" => true },
#     actions: [ { "type" => "send_template", "template" => "<uid>" } ] }
#
# Automation (the dispatcher) schedules an AutomationRun per rule and subject; the run re-checks
# the conditions when it's due and logs what ran and what was skipped. A plan feature, with a
# limit on rules switched on (BIL-01).
class AutomationRule < ApplicationRecord
  include BusinessOwned

  Trigger = Data.define(:key, :label, :subject) # subject: what the rule acts on
  TRIGGERS = [
    Trigger.new("request_received", "A request comes in", "ServiceRequest"),
    Trigger.new("quote_sent", "A quote is sent", "Quote"),
    Trigger.new("quote_viewed", "A client opens a quote", "Quote"),
    Trigger.new("quote_approved", "A quote is approved", "Quote"),
    Trigger.new("quote_declined", "A quote is declined", "Quote"),
    Trigger.new("job_completed", "A job is completed", "Job"),
    Trigger.new("visit_scheduled", "A visit is booked", "Visit"),
    Trigger.new("invoice_sent", "An invoice is sent", "Invoice"),
    Trigger.new("invoice_overdue", "An invoice becomes overdue", "Invoice"),
    Trigger.new("payment_received", "A payment is received", "Payment")
  ].index_by(&:key).freeze

  # Each condition, and the subjects it makes sense for.
  CONDITIONS = {
    "still_open" => { label: "It's still open: the quote isn't answered, the invoice isn't paid, the job isn't done", subjects: %w[Quote Job Invoice] },
    "paid_in_full" => { label: "The invoice is paid in full", subjects: %w[Invoice Payment] },
    "total_at_least" => { label: "The total is at least", subjects: %w[Quote Invoice Payment] },
    "client_tag" => { label: "The client has the tag", subjects: %w[ServiceRequest Quote Job Visit Invoice Payment] },
    "location" => { label: "It's for the location", subjects: %w[ServiceRequest Quote Job Visit Invoice Payment] } # CAT-07
  }.freeze

  # Each action, and the subjects (by trigger subject) it makes sense for.
  ACTIONS = {
    "send_template" => { label: "Email the client a template", subjects: %w[ServiceRequest Quote Job Visit Invoice Payment] },
    "notify_team" => { label: "Notify the team", subjects: %w[ServiceRequest Quote Job Visit Invoice Payment] },
    "create_job" => { label: "Create a job from the approved quote", subjects: %w[Quote] },
    "invoice_job" => { label: "Create and send an invoice for the completed job", subjects: %w[Job] },
    "tag_client" => { label: "Add a tag to the client", subjects: %w[ServiceRequest Quote Job Visit Invoice Payment] }
  }.freeze
  TEAMS = { "office" => "Everyone who runs the office", "schedule" => "Everyone who schedules" }.freeze
  MAX_DELAY_MINUTES = 90 * 24 * 60

  belongs_to :created_by, class_name: "User", optional: true
  has_many :runs, class_name: "AutomationRun", foreign_key: :rule_id, inverse_of: :rule, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :trigger, inclusion: { in: TRIGGERS.keys }
  validates :delay_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_DELAY_MINUTES, message: "can be up to 90 days" }
  # Checked when they change or the rule is turned on, so a rule whose template was deleted can
  # still be turned off.
  validate :valid_conditions, :valid_actions, if: -> { new_record? || will_save_change_to_conditions? || will_save_change_to_actions? || will_save_change_to_trigger? || (enabled? && will_save_change_to_enabled?) }
  validate :within_active_limit, if: -> { enabled? && (new_record? || will_save_change_to_enabled?) }

  scope :active, -> { where(enabled: true) }

  def trigger_definition = TRIGGERS.fetch(trigger)
  def subject_type = trigger_definition.subject
  def delay = delay_minutes.minutes

  private

  def valid_conditions
    return errors.add(:conditions, "are invalid") unless conditions.is_a?(Hash) && conditions.values.all? { [ String, TrueClass, FalseClass ].include?(_1.class) }

    unknown = conditions.keys - CONDITIONS.keys
    errors.add(:conditions, "has unknown keys: #{unknown.join(", ")}") if unknown.any?
    if TRIGGERS.key?(trigger)
      unfit = (conditions.keys & CONDITIONS.keys).reject { CONDITIONS[_1][:subjects].include?(subject_type) }
      unfit.each { errors.add(:conditions, "“#{CONDITIONS[_1][:label]}” doesn't fit “#{trigger_definition.label.downcase}”") }
    end
    if conditions.key?("total_at_least") && !(conditions["total_at_least"].to_s =~ /\A\d+(\.\d{1,2})?\z/)
      errors.add(:conditions, "need an amount like 250 or 250.00")
    end
    errors.add(:conditions, "need a tag") if conditions.key?("client_tag") && conditions["client_tag"].to_s.squish.empty?
    errors.add(:conditions, "need one of your locations") if conditions.key?("location") && !Location.exists?(uid: conditions["location"].to_s)
  end

  def valid_actions
    return errors.add(:actions, "need at least one") unless actions.is_a?(Array) && actions.any?

    actions.each do |action|
      next errors.add(:actions, "are invalid") unless action.is_a?(Hash) && action.values.all?(String)

      definition = ACTIONS[action["type"]] or next errors.add(:actions, "include an unknown one")
      errors.add(:actions, "“#{definition[:label]}” doesn't fit “#{trigger_definition.label.downcase}”") if TRIGGERS.key?(trigger) && !definition[:subjects].include?(subject_type)
      case action["type"]
      when "send_template" then errors.add(:actions, "need a template to send") unless MessageTemplate.custom.exists?(uid: action["template"])
      when "notify_team" then errors.add(:actions, "need a team to notify") unless TEAMS.key?(action["team"])
      when "tag_client" then errors.add(:actions, "need a tag to add") if action["tag"].to_s.squish.empty?
      end
    end
  end

  def within_active_limit
    entitlements = business.entitlements
    limit = entitlements.limit(:active_automations)
    return if limit.nil? || AutomationRule.unscoped.active.where(business_id:).where.not(id:).count < limit

    errors.add(:base, "Your plan includes #{limit} active #{"automation".pluralize(limit)}. Switch one off, or see plans for more.")
  end
end
