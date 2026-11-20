# PLT-10: error reporting, structured logs and performance thresholds. See lib/observability.rb
# and docs/runbooks/operations.md (Monitoring).
require Rails.root.join("lib/observability").to_s
Dir[Rails.root.join("lib/observability/*.rb")].each { require _1 }

Rails.application.configure do
  config.x.observability.structured_logs = Observability.env_flag("STRUCTURED_LOGS", Rails.env.production?)
  config.x.observability.slow_request_ms = Observability.env_integer("SLOW_REQUEST_MS", 1000)
  config.x.observability.slow_query_ms = Observability.env_integer("SLOW_QUERY_MS", 250)

  # The error tracker plugs in here once it's chosen (PLT-10 open question), for example:
  #   Observability.tracker = ->(error, payload) { SomeTracker.notify(error, payload) }
  # Until then reports go to the log only.

  Rails.error.add_middleware(Observability::ErrorContext.new)
  Rails.error.subscribe(Observability::ErrorSubscriber.new)
  log_subscriber = Observability::LogSubscriber.new
  Rails.event.subscribe(log_subscriber)
  ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") { log_subscriber.sql(_1) }

  Observability.structure_logs!(config) if config.x.observability.structured_logs
end
