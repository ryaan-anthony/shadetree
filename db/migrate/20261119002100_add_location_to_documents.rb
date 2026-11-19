# CAT-07: requests, quotes, jobs and invoices belong to a location (visits through their job).
# Existing ones go to their business's main location.
class AddLocationToDocuments < ActiveRecord::Migration[8.1]
  TABLES = %i[service_requests quotes jobs invoices].freeze

  def up
    TABLES.each do |table|
      add_reference table, :location, foreign_key: true, index: false
      execute "UPDATE #{table} SET location_id = locations.id FROM locations WHERE locations.business_id = #{table}.business_id AND locations.primary"
      change_column_null table, :location_id, false
      add_index table, %i[business_id location_id]
    end
  end

  def down
    TABLES.each do |table|
      remove_index table, %i[business_id location_id]
      remove_reference table, :location, foreign_key: true, index: false
    end
  end
end
