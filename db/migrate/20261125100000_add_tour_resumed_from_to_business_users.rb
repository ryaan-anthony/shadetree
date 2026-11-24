# ACC-08 (owner, 2026-11-24): a reload isn't leaving. The page load a reloaded tour resumed from,
# so that page's own late "end" is ignored.
class AddTourResumedFromToBusinessUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :business_users, :tour_resumed_from, :string
  end
end
