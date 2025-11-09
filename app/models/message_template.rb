class MessageTemplate < ApplicationRecord
  # Associations
  belongs_to :business
  has_many :notification_triggers, dependent: :destroy
  has_many :sent_notifications, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :event, presence: true
  validates :message_type, presence: true
  validates :message_content, presence: true

  # Enums
  enum event: {
    booking: "booking",
    reminder: "reminder",
    cancellation: "cancellation",
    payment: "payment",
    general: "general"
  }

  enum message_type: {
    email: "email",
    sms: "sms"
  }

  # Callbacks
  before_save :update_last_used_at, if: -> { usage_count_changed? && usage_count > 0 }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_event, ->(event) { where(event: event) }
  scope :by_message_type, ->(type) { where(message_type: type) }

  private

  def update_last_used_at
    self.last_used_at = Time.current
  end
end
