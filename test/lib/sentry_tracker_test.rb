require "test_helper"
require "sentry/test_helper"

# PLT-10, ADR 0027: what reaches Sentry. Events are caught by Sentry's test transport, with the
# same configuration production uses; none may carry a client's name, email, phone number,
# address or anything they wrote, and each carries release, environment and the business's id.
class SentryTrackerTest < ActionDispatch::IntegrationTest
  include Sentry::TestHelper
  include ActiveJob::TestHelper

  PERSONAL = [ "Maria", "Lopez", "maria@example.com", "maria%40example.com", "555-010-0100", "5550100100",
               "12 Elm Street", "gate code 4471", "Zelda", "Secret Lane", "s3cr3t-cookie", "Bearer abc123" ].freeze

  class FailingJob < ApplicationJob
    def perform(_name, email) = raise(ArgumentError, "No reply from #{email}, call 555-010-0100")
  end

  class BoomController < ActionController::Base
    def create
      Current.business = Business.find(params[:business_id])
      raise ArgumentError, "Could not save #{params[:client][:email]}"
    end
  end

  setup do
    Sentry.init { |config| Observability::SentryTracker.configure(config, dsn: nil) } unless Sentry.initialized?
    setup_sentry_test { |config| config.release = "0123abc"; config.environment = "staging"; config.enabled_environments = %w[staging] }
    Observability.tracker = Observability::SentryTracker.new
    @business = businesses(:one)
  end

  teardown do
    Observability.tracker = nil
    teardown_sentry_test
  end

  def assert_private(event)
    json = event.to_json_compatible.to_json
    PERSONAL.each { assert_no_match(/#{Regexp.escape(_1)}/i, json) }
    assert_nil event.to_json_compatible["request"]
    assert_empty Array(event.to_json_compatible.dig("breadcrumbs", "values"))
  end

  test "with no SENTRY_DSN, Sentry stays off" do
    previous = ENV.delete("SENTRY_DSN")
    assert_not Observability::SentryTracker.enabled?
  ensure
    ENV["SENTRY_DSN"] = previous if previous
  end

  test "the configuration sends no personal data and records no tracing" do
    config = Sentry.configuration
    assert_equal [ false, 0.0, [], false ], [ config.send_default_pii, config.traces_sample_rate, config.breadcrumbs_logger, config.data_collection.database_query_data ]
    assert_not config.data_collection.user_info
    assert_includes config.rails.skippable_job_adapters, "ActiveJob::QueueAdapters::SolidQueueAdapter"
    assert_not Rails.application.middleware.include?(Sentry::Rails::CaptureExceptions)
  end

  test "a request error arrives once, with release, environment and business id, and nothing personal" do
    with_routing do |routes|
      routes.draw { post "boom", to: "sentry_tracker_test/boom#create" }
      cookies[:visit] = "s3cr3t-cookie"
      assert_raises(ArgumentError) do
        post "/boom?q=Maria+Lopez", params: { business_id: @business.id, client: { display_name: "Maria Lopez", email: "maria@example.com",
                                              address: "12 Elm Street", notes: "gate code 4471" } },
                                    headers: { "Authorization" => "Bearer abc123", "X-Forwarded-For" => "203.0.113.9" }
      end
    end

    event = sentry_events.sole
    assert_equal [ "0123abc", "staging", "error" ], [ event.release, event.environment, event.level.to_s ]
    assert_equal @business.id.to_s, event.tags[:business_id]
    assert_equal "Could not save [EMAIL]", event.exception.values.sole.value
    assert_equal [ "POST", "/boom?q=[FILTERED]" ], event.contexts[:shadetree].values_at(:method, :path)
    assert_private(event)
  end

  test "a job error arrives once, with the job and business, and not its arguments" do
    assert_raises(ArgumentError) do
      as_business(@business) { FailingJob.perform_later("Maria Lopez", "maria@example.com") }
      perform_enqueued_jobs
    end

    event = sentry_events.sole
    assert_equal [ "SentryTrackerTest::FailingJob", @business.id.to_s, "false" ], event.tags.values_at(:job_class, :business_id, :handled)
    assert_equal "No reply from [EMAIL], call [NUMBER]", event.exception.values.sole.value
    assert_private(event)
  end

  test "database errors lose their SQL literals and row details" do
    error = assert_raises(ActiveRecord::NotNullViolation) do
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO clients (business_id, display_name, notes, created_at, updated_at)
          VALUES (#{@business.id}, 'Zelda Quartermaine', '99 Secret Lane', now(), now())
        SQL
      end
    end
    Rails.error.report(error, handled: false)

    assert_private(sentry_events.sole)
  end

  test "context, tags and extra are masked by key, whoever set them" do
    Sentry.with_scope do |scope|
      scope.set_extras(email: "maria@example.com", body: "gate code 4471", count: 2)
      scope.set_user(id: 7, email: "maria@example.com", ip_address: "203.0.113.9")
      Sentry.capture_message("boom")
    end

    event = sentry_events.sole
    assert_equal [ "[FILTERED]", "[FILTERED]", 2 ], event.extra.values_at(:email, :body, :count)
    assert_equal({ id: 7 }, event.user)
    assert_private(event)
  end

  test "an alert arrives as a warning message, grouped by its text" do
    Observability.alert("Background jobs failed", new_failures: 2, failed_classes: %w[QuotePdfJob])

    event = sentry_events.sole
    assert_equal [ "Background jobs failed", "warning", [ "alert", "Background jobs failed" ] ], [ event.message, event.level.to_s, event.fingerprint ]
    assert_equal 2, event.contexts[:shadetree][:new_failures]
  end
end
