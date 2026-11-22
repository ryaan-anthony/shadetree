# ACC-08: which first-time tips each member has seen and hidden, per business (tip key =>
# { "seen_at", "dismissed_at" }), and a person's choice to turn tips off everywhere.
class AddFirstTimeTips < ActiveRecord::Migration[8.1]
  def change
    add_column :business_users, :tips, :jsonb, default: {}, null: false
    add_column :users, :tips_off, :boolean, default: false, null: false
  end
end
