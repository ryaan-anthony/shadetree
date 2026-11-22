# CLI-07: who changed a request's follow-up and when, for its history: assigned ({ "to" }),
# reassigned ({ "from_user_id", "to_user_id" }), rescheduled ({ "from", "to" }), updated
# ({ "changed", "from", "to" }: kind, duration, instructions), unassigned ({ "from" }) and ended
# ({ "from", "reason" }: quoted or archived). "from" and "to" are RequestFollowUp#state: the
# person by id (names are looked up when shown, so a deleted account shows as a former member).
class ServiceRequestEvent < ApplicationRecord
  include BusinessOwned
  include SupportAttribution # OPS-03

  KINDS = %w[assigned reassigned rescheduled updated unassigned ended].freeze

  belongs_to_business_record :service_request
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(request, kind, by:, **data)
    create!(business: request.business, service_request: request, kind: kind.to_s, user: by, data: data.compact, occurred_at: Time.current)
  end

  # The people the history names, by id.
  def user_ids = [ data["from_user_id"], data["to_user_id"], data.dig("from", "user_id"), data.dig("to", "user_id") ].compact
end
