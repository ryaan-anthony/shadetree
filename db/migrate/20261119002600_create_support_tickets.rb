# OPS-05: a business asking Shadetree for help. A ticket and its thread of messages (from the
# member, from operators, and operators' internal notes), with the page and browser it came from.
class CreateSupportTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :support_tickets do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false, index: { unique: true }
      t.references :opened_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :assignee, foreign_key: { to_table: :users, on_delete: :nullify } # an operator
      t.string :subject, null: false
      t.string :category, null: false
      t.string :status, null: false, default: "open"
      t.string :page # the app page it was opened from (a path)
      t.string :browser # the user agent
      t.datetime :last_message_at, null: false
      t.datetime :waiting_since # when it became "Waiting on you"
      t.datetime :resolved_at
      t.timestamps

      t.index %i[status last_message_at]
      t.check_constraint "status IN ('open', 'waiting', 'resolved')", name: "support_tickets_status"
      t.check_constraint "category IN ('question', 'bug', 'billing', 'feature')", name: "support_tickets_category"
    end

    create_table :support_messages do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :support_ticket, null: false, foreign_key: { on_delete: :cascade }
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.boolean :from_operator, null: false, default: false
      t.boolean :internal, null: false, default: false # an operator's note, never shown to the business
      t.string :source, null: false, default: "app" # app, email or system
      t.text :body, null: false
      t.timestamps
    end
  end
end
