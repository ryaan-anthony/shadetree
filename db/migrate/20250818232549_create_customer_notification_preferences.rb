class CreateCustomerNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :customer_notification_preferences do |t|
      t.references :customer, null: false, foreign_key: { to_table: :users }
      t.references :business, null: false, foreign_key: true
      t.boolean :email_notifications, default: true
      t.boolean :sms_notifications, default: true
      t.boolean :booking_confirmations, default: true
      t.boolean :appointment_reminders, default: true
      t.boolean :payment_notifications, default: true
      t.boolean :promotional_messages, default: false

      t.timestamps
    end

    # Add a unique index to ensure one preference set per customer/business
    add_index :customer_notification_preferences, [ :customer_id, :business_id ], unique: true, name: 'index_customer_notification_prefs_on_customer_and_business'
  end
end
