# OPS-05: Action Mailbox's table (from `bin/rails action_mailbox:install`) for email to the support
# address, plus what the Cloudflare Email Worker vouches for in its signed request: the envelope
# sender and recipient, and Cloudflare's own Authentication-Results from the raw message (one copy
# per recipient: a Cc to support@ and support+<token>@ is stored twice). The raw message is an Active
# Storage file; both go after 14 days (incineration, PurgeInboundEmailsJob).
class CreateActionMailboxTables < ActiveRecord::Migration[8.1]
  def change
    create_table :action_mailbox_inbound_emails do |t|
      t.integer :status, default: 0, null: false
      t.string :message_id, null: false
      t.string :message_checksum, null: false
      t.string :envelope_from
      t.string :envelope_to
      t.text :auth_results

      t.timestamps

      t.index [ :message_id, :message_checksum, :envelope_to ], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
      t.index :created_at
    end
  end
end
