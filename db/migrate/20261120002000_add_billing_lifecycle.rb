# BIL-05: a business's trial of a paid plan, a plan an operator comps (with an optional end,
# OPS-04), when a failing renewal started (for the grace period), the billing status the
# operator directory filters on, and when the plan next needs working out again (a trial, comp
# or grace period ending), so a scheduled check finds those businesses without reading every
# subscription.
class AddBillingLifecycle < ActiveRecord::Migration[8.1]
  def change
    change_table :businesses, bulk: true do |t|
      t.references :trial_plan, foreign_key: { to_table: :plans }, index: false
      t.datetime :trial_ends_at
      t.integer :trial_reminded_days # the last "ends in N days" email sent
      t.references :comp_plan, foreign_key: { to_table: :plans }, index: false
      t.datetime :comp_ends_at
      t.string :billing_status, null: false, default: "free"
      t.datetime :billing_check_at
    end
    add_index :businesses, :billing_status
    add_index :businesses, :billing_check_at, where: "billing_check_at IS NOT NULL"
    add_column :subscriptions, :past_due_since, :datetime
  end
end
