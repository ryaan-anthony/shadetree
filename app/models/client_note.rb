# A note staff add to a client's timeline (CLI-05). Only the team sees it; its author can edit it.
class ClientNote < ApplicationRecord
  include BusinessOwned

  belongs_to_business_record :client
  belongs_to :user, optional: true
  has_one :event, -> { where(kind: "note_added") }, class_name: "ClientEvent", as: :subject, dependent: :delete

  normalizes :body, with: ->(value) { value.to_s.strip }
  validates :body, presence: { message: "can't be empty" }, length: { maximum: 5_000 }

  after_create { ClientEvent.record!(client, :note_added, subject: self, by: user) }

  def editable_by?(user) = user_id.present? && user_id == user&.id
end
