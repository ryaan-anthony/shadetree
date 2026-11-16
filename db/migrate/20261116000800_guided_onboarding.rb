# ACC-05: the setup checklist replaces the old step-based flow. onboarding_step is gone;
# onboarded_at now means the owner finished or dismissed the checklist. The time from sign-up
# to the first quote sent is kept per business (a product metric: a timestamp, no PII), and a
# technician's one-screen welcome is dismissed per membership.
class GuidedOnboarding < ActiveRecord::Migration[8.1]
  def change
    remove_column :businesses, :onboarding_step, :string
    add_column :businesses, :first_quote_sent_at, :datetime
    add_column :business_users, :welcome_dismissed_at, :datetime
  end
end
