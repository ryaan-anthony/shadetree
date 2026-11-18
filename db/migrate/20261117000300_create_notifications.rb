# NTF-02: in-app notifications for team members, and each member's email choices.
#
# A notification is one member's copy of an event ("Maria approved Q-0042"): its text and the
# path it opens are stored when it's raised, so the list needs no other table and still reads
# right after the record changes. Email choices are per membership (a member of two businesses
# chooses for each), as { "quote_viewed" => true }; a type not listed uses the type's default.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :uid, null: false
      t.string :kind, null: false
      t.references :subject, polymorphic: true, index: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.string :title, null: false
      t.string :body
      t.string :path, null: false
      t.datetime :read_at
      t.datetime :created_at, null: false
    end
    add_index :notifications, :uid, unique: true
    add_index :notifications, %i[business_id user_id created_at]
    add_index :notifications, %i[business_id user_id], where: "read_at IS NULL", name: "index_notifications_unread"
    add_index :notifications, :created_at # pruning

    add_column :business_users, :notification_emails, :jsonb, null: false, default: {}
  end
end
