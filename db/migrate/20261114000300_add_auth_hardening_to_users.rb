# ACC-01: lockout after repeated failures, recorded terms acceptance, and a session token that
# "sign out of all devices" rotates.
class AddAuthHardeningToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.integer :failed_attempts, null: false, default: 0
      t.string :unlock_token
      t.datetime :locked_at
      t.datetime :terms_accepted_at
      t.string :session_token
    end
    add_index :users, :unlock_token, unique: true
  end
end
