# OPS-01: the audit log is append-only in the database too. schema.rb can't hold triggers, so
# whatever builds a database from it (db:prepare on a fresh deploy or restore, db:schema:load,
# the test database) adds them afterwards; migrations add them where the schema is migrated.
# AuditEntry.append_only? checks, and the console's home warns if they're missing.
module AuditLogTrigger
  def self.install(environment)
    tasks = ActiveRecord::Tasks::DatabaseTasks
    tasks.send(:each_current_configuration, environment) do |db_config|
      tasks.with_temporary_connection(db_config) { |connection| AuditEntry.install_append_only_trigger!(connection) }
    end
  end
end

{ "db:schema:load" => nil, "db:prepare" => nil, "db:test:load_schema" => "test" }.each do |name, environment|
  next unless Rake::Task.task_defined?(name)

  Rake::Task[name].enhance { AuditLogTrigger.install(environment || ActiveRecord::Tasks::DatabaseTasks.env) }
end
