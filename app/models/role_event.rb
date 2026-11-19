# ACC-07: what happened to a custom role, and who did it: created, changed (permissions or
# name, before and after), deleted (and where its members went), given to or taken from a
# member (by user id, so the name isn't kept once their account is deleted).
class RoleEvent < ApplicationRecord
  include BusinessOwned
  include SupportAttribution # OPS-03

  KINDS = %w[created changed deleted assigned unassigned].freeze

  belongs_to :role, optional: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }

  def self.record!(role, kind, by:, **data)
    create!(business: role.business, role:, user: by, kind:, data: data.merge(role_name: role.name), occurred_at: Time.current)
  end
end
