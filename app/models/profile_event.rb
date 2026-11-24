# ACC-09: a change someone else made to a member's profile: who (user, or support viewing as
# them, OPS-03), which fields (never their values, so nothing personal is kept), and when. Shown
# in a history on the member's Team row.
class ProfileEvent < ApplicationRecord
  include BusinessOwned
  include SupportAttribution # OPS-03

  belongs_to :business_user
  belongs_to :user, optional: true # who made the change

  validate { errors.add(:data, "must list changed fields") unless (Array(data["changed"]) - TeamProfile::FIELDS.keys).empty? && Array(data["changed"]).any? }

  def self.record!(member, fields, by:)
    Tenancy.with_business(member.business) do
      create!(business: member.business, business_user: member, user: by, data: { "changed" => fields }, occurred_at: Time.current)
    end
  end

  def changed_fields = Array(data["changed"])

  # "photo and title"
  def summary = changed_fields.map { TeamProfile::FIELDS.fetch(_1) }.to_sentence
end
