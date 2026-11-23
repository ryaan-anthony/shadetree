# PLT-10, ADR 0027: check that Sentry is wired up after setting SENTRY_DSN. Sends one test error
# and one test alert the way the app sends real ones (through Rails.error, scrubbed), then waits
# for them to leave. See docs/runbooks/operations.md, "Set up Sentry".
namespace :sentry do
  desc "Send a test error and a test alert to Sentry (needs SENTRY_DSN)"
  task test: :environment do
    abort "SENTRY_DSN is not set, so Sentry is off and nothing was sent." unless Observability::SentryTracker.enabled? && Sentry.initialized?

    Observability::SentryTracker.send_test!
    puts "Sent a test error (ZeroDivisionError) and a test alert (\"Sentry test message\") to " \
         "#{Observability.environment}. They should appear in Sentry's Issues within a minute."
  end
end
