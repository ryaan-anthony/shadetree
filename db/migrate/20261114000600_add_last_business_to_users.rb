# ACC-02: remember the business a user last chose, across sessions and devices.
class AddLastBusinessToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :last_business, foreign_key: { to_table: :businesses, on_delete: :nullify }
  end
end
