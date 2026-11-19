# OPS-04: an operator suspends a business (it stops being active) with a reason, and can
# reactivate it. A business that isn't active and has no suspension was closed (ACC-06).
class AddSuspensionToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :suspended_at, :datetime
    add_column :businesses, :suspension_reason, :text
  end
end
