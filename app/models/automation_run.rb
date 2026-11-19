# NTF-04: one rule acting on one record: scheduled when its trigger happens, then run when its
# delay ends. The log says what ran and what was skipped, and why, for the automation page and
# the record's own page. At most one run per rule and record.
class AutomationRun < ApplicationRecord
  include BusinessOwned

  STATUSES = %w[scheduled done skipped failed].freeze

  belongs_to :rule, class_name: "AutomationRule", optional: true, inverse_of: :runs
  belongs_to :subject, polymorphic: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :due, -> { where(status: "scheduled").where(run_at: ..Time.current) }

  def note!(action, result, detail = nil) = log << { "action" => action, "result" => result, "detail" => detail }.compact
end
