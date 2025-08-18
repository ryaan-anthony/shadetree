class NotificationTrigger < ApplicationRecord
  # Associations
  belongs_to :business
  belongs_to :message_template
  has_many :sent_notifications, dependent: :destroy

  # Validations
  validates :trigger_name, presence: true
  validates :trigger_event, presence: true

  # Default values
  attribute :timing_offset, :integer, default: 0
  attribute :is_active, :boolean, default: true
  attribute :trigger_count, :integer, default: 0

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_event, ->(event) { where(trigger_event: event) }

  # JSON accessors
  store_accessor :trigger_conditions, [], prefix: true
  store_accessor :delivery_channels, [], prefix: true

  # Event types could be defined as an enum
  # This would depend on your specific application needs
  # enum trigger_event: {
  #   appointment_booked: 'appointment_booked',
  #   appointment_confirmed: 'appointment_confirmed',
  #   appointment_cancelled: 'appointment_cancelled',
  #   payment_received: 'payment_received',
  #   # Add other event types as needed
  # }

  # Callbacks
  before_save :update_last_triggered_at, if: -> { trigger_count_changed? && trigger_count > 0 }

  private

  def update_last_triggered_at
    self.last_triggered_at = Time.current
  end
end
