# OPS-01: the audit log is append-only in the database too. schema.rb can't hold triggers, so
# every schema load (setup, CI, the test database) adds it after the tables; migrations add it
# in deployed environments (AuditEntry.install_append_only_trigger!).
%w[db:schema:load db:test:load_schema].each do |name|
  next unless Rake::Task.task_defined?(name)

  Rake::Task[name].enhance do
    if name == "db:test:load_schema"
      ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations.configs_for(env_name: "test").first)
    end
    AuditEntry.install_append_only_trigger!
  end
end
