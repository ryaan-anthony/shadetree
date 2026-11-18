# NTF-02: one team member's copy of something that happened ("Maria approved Q-0042"), shown in
# the notification center in the business it happened in. Raised through
# NotificationType.deliver, which also sends the email when the member wants one.
class Notification < ApplicationRecord
  include BusinessOwned

  RETENTION = 90.days
  LIST_SIZE = 100

  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, inclusion: { in: ->(_) { NotificationType.kinds } }
  validates :title, presence: true, length: { maximum: 200 }
  validates :body, length: { maximum: 300 }
  validates :path, presence: true, format: { with: %r{\A/admin(/[^\s\\]*)?\z} } # only a page in the staff app (it is redirected to)

  normalizes :body, with: ->(body) { body.to_s.squish.truncate(300).presence }

  scope :for_user, ->(user) { where(user:) }
  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def read? = read_at.present?
  def type = NotificationType.fetch(kind)

  def mark_read! = (update_columns(read_at: Time.current) unless read?)

  # Older notifications go; a daily job runs this (config/recurring.yml).
  def self.prune!(before: RETENTION.ago)
    Tenancy.across_businesses(reason: "pruning old notifications") { where(created_at: ...before).in_batches(of: 1_000).delete_all }
  end
end
