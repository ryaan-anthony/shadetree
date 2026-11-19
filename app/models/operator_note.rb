# OPS-02: an operator's internal note on a business: who wrote it and when. Internal only (the
# business never sees it); only its author edits or deletes it. Platform data, not owned by the
# business, so it isn't tenant-scoped.
class OperatorNote < ApplicationRecord
  belongs_to :business
  belongs_to :author, class_name: "User", optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }
  validates :body, presence: true, length: { maximum: 5_000 }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def written_by?(user) = author_id.present? && author_id == user&.id
end
