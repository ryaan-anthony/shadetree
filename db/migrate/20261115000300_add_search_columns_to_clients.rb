# CLI-02 (1/3): the columns search and the "recent activity" sort need. Both have defaults,
# so code still running from the previous release can keep inserting clients during a
# deploy, and adding them doesn't rewrite the table (PostgreSQL 11+ stores constant and
# now() defaults without touching existing rows).
#
# search_text is a lowercased digest of the client's name, company, emails, phones (as typed
# and as digits) and property addresses; Client.refresh_search_text keeps it current.
class AddSearchColumnsToClients < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    add_column :clients, :search_text, :text, null: false, default: ""
    add_column :clients, :last_activity_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
  end
end
