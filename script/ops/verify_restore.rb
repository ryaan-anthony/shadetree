# Sanity checks for a restored database (Backup workflow restore drill, PLT-09).
# Fails loudly if the restore is empty, behind on migrations, or missing core tables.
connection = ActiveRecord::Base.connection
pending = ActiveRecord::Base.connection_pool.migration_context.needs_migration?
abort "Restored schema is behind the code: run migrations or check the dump" if pending

counts = %w[users businesses business_users].to_h { |table| [ table, connection.select_value("SELECT count(*) FROM #{table}").to_i ] }
abort "Restored database has no users or businesses" if counts.values_at("users", "businesses").any?(&:zero?)

newest = connection.select_value("SELECT max(updated_at) FROM businesses")
puts "Restore OK: #{counts.map { |t, n| "#{n} #{t}" }.join(", ")}; newest business change #{newest} UTC"
