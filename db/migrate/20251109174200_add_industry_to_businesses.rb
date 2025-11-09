class AddIndustryToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :industry, :string
    add_index :businesses, :industry
  end
end
