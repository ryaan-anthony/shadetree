class AddOnboardingFieldsToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :onboarded_at, :datetime
    add_column :businesses, :onboarding_step, :string
    add_index :businesses, :onboarded_at
    add_index :businesses, :onboarding_step
  end
end
