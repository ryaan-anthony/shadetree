# OPS-04: an operator schedules a business for permanent deletion; after the waiting period a
# daily job removes it and all its data and files. Cancelling clears both.
class AddDeletionScheduleToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :deletion_scheduled_at, :datetime
    add_column :businesses, :deletion_due_at, :datetime
    add_index :businesses, :deletion_due_at, where: "deletion_due_at IS NOT NULL"
  end
end
