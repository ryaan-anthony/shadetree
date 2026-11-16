# QTE-03: an expired quote's client can ask for an updated one; staff see when they did.
class AddClientPageFieldsToQuotes < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :update_requested_at, :datetime
  end
end
