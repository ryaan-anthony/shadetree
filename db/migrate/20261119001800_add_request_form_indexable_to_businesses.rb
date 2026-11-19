# MKT-04: a business can let search engines find its request page (off by default).
class AddRequestFormIndexableToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :request_form_indexable, :boolean, default: false, null: false
  end
end
