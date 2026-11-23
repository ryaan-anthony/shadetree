# ACC-09: "Show team profiles to clients" (Settings → Messages), off by default.
class AddShowTeamProfilesToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :show_team_profiles, :boolean, null: false, default: false
  end
end
