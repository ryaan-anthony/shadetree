# PLT-10: error reporting, structured logs and performance thresholds. See lib/observability.rb
# and docs/runbooks/operations.md (Monitoring).
require Rails.root.join("lib/observability").to_s
Dir[Rails.root.join("lib/observability/*.rb")].each { require _1 }

Rails.application.configure do
  config.x.observability.structured_logs = Observability.env_flag("STRUCTURED_LOGS", Rails.env.production?)
  config.x.observability.slow_request_ms = Observability.env_integer("SLOW_REQUEST_MS", 1000)
  config.x.observability.slow_query_ms = Observability.env_integer("SLOW_QUERY_MS", 250)
  config.x.observability.job_backlog_threshold = Observability.env_integer("JOB_BACKLOG_THRESHOLD", 100)
  config.x.observability.job_wait_threshold = Observability.env_integer("JOB_WAIT_THRESHOLD", 600)

  config.x.observability.job_failed_threshold = Observability.env_integer("JOB_FAILED_THRESHOLD", 1)
  config.x.observability.job_alert_repeat_minutes = Observability.env_integer("JOB_ALERT_REPEAT_MINUTES", 60)
  # Where nightly backups run (staging and production): stale or untested ones raise an alert.
  config.x.observability.backup_alerts = Observability.env_flag("BACKUP_ALERTS", Rails.env.production?)

  # The error tracker (ADR 0027): Sentry, only with SENTRY_DSN (staging and production). Its own
  # request capture is taken out of the stack; everything reaches it through ErrorSubscriber.
  config.middleware.delete Sentry::Rails::CaptureExceptions
  config.middleware.delete Sentry::Rails::RescuedExceptionInterceptor
  if Observability::SentryTracker.enabled?
    Sentry.init { Observability::SentryTracker.configure(_1) }
    Observability.tracker = Observability::SentryTracker.new
  end

  Rails.error.add_middleware(Observability::ErrorContext.new)
  Rails.error.subscribe(Observability::ErrorSubscriber.new)
  log_subscriber = Observability::LogSubscriber.new
  Rails.event.subscribe(log_subscriber)
  ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") { log_subscriber.sql(_1) }

  Observability.structure_logs!(config) if config.x.observability.structured_logs
end
