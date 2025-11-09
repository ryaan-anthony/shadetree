class AddAddressAndDescriptionToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :address, :text
    add_column :businesses, :description, :text
  end
end
