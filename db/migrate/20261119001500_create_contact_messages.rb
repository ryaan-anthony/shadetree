# MKT-02: messages sent through the marketing site's contact form. Platform-level (no business).
class CreateContactMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_messages do |t|
      t.string :uid, null: false
      t.string :name, null: false
      t.string :email, null: false
      t.string :business_name
      t.string :industry
      t.text :body, null: false
      t.string :spam_reason # set when it looked like spam: kept for review, nobody notified
      t.string :ip_address
      t.string :user_agent
      t.datetime :notified_at
      t.timestamps
    end
    add_index :contact_messages, :uid, unique: true
    add_index :contact_messages, :email
    add_index :contact_messages, :created_at
  end
end
