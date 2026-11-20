require "test_helper"

# PLT-10: errors and alerts reach the log and the tracker hook with their context, minus
# anything personal; slow queries are logged without their literal values.
class ObservabilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FailingJob < ApplicationJob
    def perform(_client) = raise(ArgumentError, "No reply from maria@example.com or +1 (555) 010-0100")
  end

  class RetryingJob < ApplicationJob
    retry_on(IOError, wait: 1.minute, attempts: 3)
    def perform = raise(IOError, "mail server 555-010-0100 busy")
  end

  class DiscardingJob < ApplicationJob
    discard_on(IOError)
    def perform = raise(IOError, "gone")
  end

  setup do
    @reports = []
    Observability.tracker = ->(error, payload) { @reports << [ error, payload ] }
    @business = businesses(:one)
  end

  teardown { Observability.tracker = nil }

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io, level: :info, formatter: Observability::JsonLogFormatter.new))
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  test "release and environment come from the deploy's APP_REVISION and APP_ENVIRONMENT (PLT-09)" do
    previous = %w[APP_REVISION APP_ENVIRONMENT].index_with { ENV[_1] }
    ENV.update("APP_REVISION" => "0123abc", "APP_ENVIRONMENT" => "staging")
    Rails.error.report(RuntimeError.new("boom"), handled: true)
    assert_equal %w[0123abc staging], @reports.sole.last.values_at(:release, :environment)

    ENV.delete("APP_REVISION")
    ENV.delete("APP_ENVIRONMENT")
    assert_equal "development", Observability.release
  ensure
    previous.each { ENV[_1] = _2 }
  end

  test "an unhandled job error is reported with the job, business and release, and no personal data" do
    client = as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "555-010-0100" } ]) }
    log = capture_log do
      assert_raises(ArgumentError) { as_business(@business) { FailingJob.perform_later(client) }; perform_enqueued_jobs }
    end

    error, payload = @reports.sole
    assert_kind_of ArgumentError, error
    assert_equal "ObservabilityTest::FailingJob", payload[:job_class]
    assert_equal @business.id, payload[:business_id]
    assert_equal [ false, :error, "test" ], payload.values_at(:handled, :severity, :environment)
    assert payload[:release].present?
    assert_equal "No reply from [EMAIL] or [NUMBER]", payload[:message]
    assert_nil payload[:job]
    assert_match %r{test/lib/observability_test.rb}, payload[:location]
    assert_equal payload[:location], payload[:backtrace].first
    assert_operator payload[:backtrace].size, :<=, 10
    assert payload[:backtrace].none? { _1.include?("/gems/") }

    line = log.lines.grep(/"event":"error"/).sole
    assert_equal [ "ObservabilityTest::FailingJob", payload[:job_id], "ERROR" ], JSON.parse(line).values_at("job_class", "job_id", "level")
    [ "maria", "010-0100", "Maria Lopez" ].each { assert_no_match _1, line }
  end

  test "a request error carries the request id, method and path, with link tokens blanked" do
    controller = ClientLinksController.new
    controller.request = ActionDispatch::TestRequest.create("PATH_INFO" => "/c/s3cr3tt0ken", "action_dispatch.request_id" => "req-1")
    context = Observability::ErrorContext.new.call(RuntimeError.new, context: { controller: }, handled: false, severity: :error, source: "x")

    assert_equal [ "req-1", "GET", "/c/[FILTERED]" ], context.values_at(:request_id, :method, :path)
    assert_not context.key?(:controller)
  end

  test "context the app passes is filtered, and records become global ids" do
    client = as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "555-010-0100" } ]) }
    as_business(@business) do
      Rails.error.report(RuntimeError.new("boom"), context: { email: "maria@example.com", client:, note: "call 555 010 0100", count: 3 })
    end

    payload = @reports.sole.last
    assert_equal "[FILTERED]", payload[:email]
    assert_equal client.to_global_id.to_s, payload[:client]
    assert_equal "call [NUMBER]", payload[:note]
    assert_equal [ 3, @business.id, true, :warning ], payload.values_at(:count, :business_id, :handled, :severity)
  end

  test "alerts take the same road, logged as warnings" do
    log = capture_log { Observability.alert("3 jobs failed", failed: 3) }

    error, payload = @reports.sole
    assert_kind_of Observability::Alert, error
    assert_equal [ "3 jobs failed", 3, "shadetree.alert" ], payload.values_at(:message, :failed, :source)
    assert_match(/"event":"alert"/, log)
  end

  test "a database error's row and key details stay out of the report" do
    error = assert_raises(ActiveRecord::NotNullViolation) do
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO clients (business_id, display_name, notes, created_at, updated_at)
          VALUES (#{@business.id}, 'Zelda Quartermaine', '99 Secret Lane', now(), now())
        SQL
      end
    end
    assert_match "99 Secret Lane", error.message # Postgres put the row in the message…
    log = capture_log { Rails.error.report(error) }

    assert_match(/\APG::NotNullViolation: ERROR:  null value in column "uid"/, @reports.sole.last[:message])
    [ "Secret Lane", "Zelda", "DETAIL" ].each { assert_no_match _1, log } # …and none of it is logged
  end

  test "scrubbing masks addresses and phone-like numbers, and leaves dates, times, ids and IPs" do
    assert_equal "to [EMAIL], tel [NUMBER], id 42", Observability.scrub("to a.b+c@mail.example.co, tel 555-010-0100, id 42")
    assert_equal "[EMAIL] or [NUMBER] or [NUMBER]", Observability.scrub("maria%40example.com or +1 (555) 010-0100 or 5550100100")
    kept = "at 2026-11-19 10:00:00 UTC, id=12345678, from 10.0.0.12, job d129ad83-1137-4243-957c-63c7a13c75e4, client 1234567"
    assert_equal kept, Observability.scrub(kept)
    assert_equal "SELECT 1 WHERE email = '?' AND id = $1", Observability.scrub_sql("SELECT 1 WHERE email = 'o''neil@example.com'  AND id = $1")
  end

  test "retries and discards are logged as warnings, with scrubbed messages" do
    config = Rails.configuration.x.observability
    config.structured_logs = true
    log = capture_log { RetryingJob.perform_now; DiscardingJob.perform_now }
    lines = log.lines.map { JSON.parse(_1) }.index_by { _1["event"] }

    retry_line = lines.fetch("job_retry")
    assert_equal [ "WARN", "ObservabilityTest::RetryingJob", "mail server [NUMBER] busy" ], retry_line.values_at("level", "job_class", "error_message")
    assert_includes 60..70, retry_line["wait_seconds"] # a minute plus jitter
    assert_equal [ "WARN", "IOError" ], lines.fetch("job_discarded").values_at("level", "error_class")
    assert_equal "INFO", lines.fetch("job")["level"] # a handled failure isn't an error
    assert_empty @reports
  ensure
    config.structured_logs = false
  end

  test "slow queries are logged with their source and without values" do
    config = Rails.configuration.x.observability
    saved = config.slow_query_ms
    config.slow_query_ms = 0
    log = capture_log { User.where("email = 'nobody@example.com'").to_a }
    config.slow_query_ms = saved

    line = JSON.parse(log.lines.grep(/"event":"slow_query"/).grep(/users/).first)
    assert_match "email = '?'", line["sql"]
    assert_match "test/lib/observability_test.rb", line["source"]
    assert_no_match "nobody@example.com", log
  end
end
