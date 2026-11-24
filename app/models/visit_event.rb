# JOB-02: who changed a visit and when, for its history: scheduled ({ "to", "crew" }),
# rescheduled ({ "from", "to" }: Visit#snapshot, a label and the values), reassigned ({ "added",
# "removed" } names and ids), updated ({ "changed" } duration/instructions), cancelled
# ({ "reason" }), restored, started, completed, reopened, on_the_way (JOB-12: { "arrives_at",
# "emailed", "why_not" }; the sender is the event's user, so no name is stored).
class VisitEvent < ApplicationRecord
  include BusinessOwned
  include SupportAttribution # OPS-03

  KINDS = %w[scheduled rescheduled reassigned updated cancelled restored started completed reopened on_the_way].freeze

  belongs_to_business_record :visit
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(visit, kind, by:, **data)
    create!(business: visit.business, visit:, kind: kind.to_s, user: by, data:, occurred_at: Time.current)
  end
end
