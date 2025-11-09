class CustomerNotificationPreference < ApplicationRecord
  # Associations
  belongs_to :customer, class_name: "User"
  belongs_to :business

  # Default values for preferences
  attribute :email_notifications, :boolean, default: true
  attribute :sms_notifications, :boolean, default: true
  attribute :booking_confirmations, :boolean, default: true
  attribute :appointment_reminders, :boolean, default: true
  attribute :payment_notifications, :boolean, default: true
  attribute :promotional_messages, :boolean, default: false

  # Validations
  validates :customer_id, presence: true
  validates :business_id, presence: true
  validates :customer_id, uniqueness: { scope: :business_id, message: "notification preferences already exist for this customer and business" }

  # Scopes
  scope :email_enabled, -> { where(email_notifications: true) }
  scope :sms_enabled, -> { where(sms_notifications: true) }
  scope :promo_enabled, -> { where(promotional_messages: true) }

  # Instance methods

  # Check if any notifications are enabled for this customer
  def notifications_enabled?
    email_notifications || sms_notifications
  end

  # Check if a specific notification type is enabled
  def notification_type_enabled?(type)
    return false unless notifications_enabled?

    case type.to_sym
    when :booking
      booking_confirmations
    when :reminder
      appointment_reminders
    when :payment
      payment_notifications
    when :promotion
      promotional_messages
    else
      false
    end
  end
end
