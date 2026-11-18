# JOB-02: who changed a visit and when, for its history: scheduled, rescheduled ({ "from", "to" }
# as labels), reassigned ({ "added", "removed" } names), cancelled ({ "reason" }), restored,
# started, completed, reopened.
class VisitEvent < ApplicationRecord
  include BusinessOwned

  KINDS = %w[scheduled rescheduled reassigned cancelled restored started completed reopened].freeze

  belongs_to_business_record :visit
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(visit, kind, by:, **data)
    create!(business: visit.business, visit:, kind: kind.to_s, user: by, data:, occurred_at: Time.current)
  end
end
