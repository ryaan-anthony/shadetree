# NTF-01: every client-facing email is recorded per business with its delivery outcome, and
# addresses that hard-bounce or complain are suppressed for that business.
class CreateEmailTracking < ActiveRecord::Migration[8.1]
  def change
    create_table :email_messages do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :kind, null: false
      t.string :to, null: false
      t.string :subject
      t.references :related, polymorphic: true
      t.string :status, null: false, default: "queued"
      t.string :provider_message_id
      t.text :error
      t.integer :attempts, null: false, default: 0
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :bounced_at
      t.datetime :complained_at
      t.datetime :failed_at
      t.timestamps
    end
    add_index :email_messages, :uid, unique: true
    add_index :email_messages, :provider_message_id, unique: true
    add_index :email_messages, %i[business_id created_at]
    add_check_constraint :email_messages,
                         "status IN ('queued', 'sent', 'delivered', 'bounced', 'complained', 'failed', 'suppressed')",
                         name: "email_messages_status"

    create_table :email_suppressions do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :email, null: false # lowercased
      t.string :reason, null: false # hard_bounce, complaint
      t.references :email_message, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :email_suppressions, %i[business_id email], unique: true

    # Shown on the client: this address bounced or complained, until staff fix it.
    add_column :client_contact_methods, :undeliverable_at, :datetime
    add_column :client_contact_methods, :undeliverable_reason, :string
  end
end
