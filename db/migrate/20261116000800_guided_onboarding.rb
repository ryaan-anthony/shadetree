# ACC-05: the setup checklist replaces the old step-based flow.
# - onboarded_at now means the checklist was finished. Each Owner or Admin can also hide it for
#   themselves (business_users.setup_hidden_at), and a technician's one-screen welcome is
#   dismissed per membership.
# - The time to the first quote sent is kept per business (a product metric: a timestamp, no
#   PII), backfilled for businesses that already sent one, which count as onboarded.
# - onboarding_step is ignored by the app now (Business.ignored_columns) and dropped in a later
#   migration, so servers running the old code during the deploy don't break.
class GuidedOnboarding < ActiveRecord::Migration[8.1]
  def up
    add_column :businesses, :first_quote_sent_at, :datetime
    add_column :business_users, :welcome_dismissed_at, :datetime
    add_column :business_users, :setup_hidden_at, :datetime

    execute <<~SQL
      UPDATE businesses SET first_quote_sent_at = firsts.sent_at, onboarded_at = COALESCE(businesses.onboarded_at, firsts.sent_at)
      FROM (SELECT business_id, MIN(sent_at) AS sent_at FROM quotes WHERE sent_at IS NOT NULL GROUP BY business_id) firsts
      WHERE firsts.business_id = businesses.id
    SQL
  end

  def down
    remove_column :business_users, :setup_hidden_at
    remove_column :business_users, :welcome_dismissed_at
    remove_column :businesses, :first_quote_sent_at
  end
end
