# BIL-05: a business's trial of a paid plan, a plan an operator comps (with an optional end,
# OPS-04), when a failing renewal started (for the grace period), the billing status the
# operator directory filters on, and when the plan next needs working out again (a trial, comp
# or grace period ending), so a scheduled check finds those businesses without reading every
# subscription.
#
# Businesses already on a paid plan without a live subscription (set by an operator before
# billing existed) keep it as a comp with no end date, so nobody is moved to Free or emailed;
# businesses with a live subscription get their billing status.
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
    reversible { |direction| direction.up { set_existing_billing } }
  end

  LIVE = "('active', 'trialing', 'past_due')".freeze

  def set_existing_billing
    execute <<~SQL.squish
      UPDATE businesses SET comp_plan_id = businesses.plan_id, billing_status = 'comped'
      FROM plans
      WHERE plans.id = businesses.plan_id AND (plans.monthly_price_cents > 0 OR plans.annual_price_cents > 0)
        AND NOT EXISTS (SELECT 1 FROM subscriptions WHERE subscriptions.business_id = businesses.id AND subscriptions.status IN #{LIVE})
    SQL
    execute <<~SQL.squish
      UPDATE businesses SET billing_status = CASE subscriptions.status WHEN 'past_due' THEN 'past_due' ELSE 'active' END
      FROM subscriptions
      WHERE subscriptions.business_id = businesses.id AND subscriptions.status IN #{LIVE}
    SQL
  end
end
