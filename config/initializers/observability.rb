# PLT-10: error reporting, structured logs and performance thresholds. See lib/observability.rb
# and docs/runbooks/operations.md (Monitoring).
require Rails.root.join("lib/observability").to_s
Dir[Rails.root.join("lib/observability/*.rb")].each { require _1 }

Rails.application.configure do
  config.x.observability.structured_logs = ENV.fetch("STRUCTURED_LOGS", Rails.env.production?.to_s) == "true"
  config.x.observability.slow_request_ms = Integer(ENV.fetch("SLOW_REQUEST_MS", 1000))
  config.x.observability.slow_query_ms = Integer(ENV.fetch("SLOW_QUERY_MS", 250))

  # The error tracker plugs in here once it's chosen (PLT-10 open question), for example:
  #   Observability.tracker = ->(error, payload) { SomeTracker.notify(error, payload) }
  # Until then reports go to the log only.

  Rails.error.add_middleware(Observability::ErrorContext.new)
  Rails.error.subscribe(Observability::ErrorSubscriber.new)
  log_subscriber = Observability::LogSubscriber.new
  Rails.event.subscribe(log_subscriber)
  ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") { log_subscriber.sql(_1) }

  if config.x.observability.structured_logs
    # One JSON line per request and job replaces Rails' text lines, whose messages can carry
    # values (an exception message, a mail server's reply quoting an address) and the client IP.
    config.action_dispatch.debug_exception_log_level = :debug
    ActiveSupport.on_load(:action_controller) { ActionController::LogSubscriber.detach_from(:action_controller) }
    ActiveSupport.on_load(:action_view) { ActionView::LogSubscriber.detach_from(:action_view) }
    ActiveSupport.on_load(:active_job) { ActiveJob::LogSubscriber.detach_from(:active_job) }
    ActiveSupport.on_load(:action_mailer) { ActionMailer::LogSubscriber.detach_from(:action_mailer) }
  end
end
