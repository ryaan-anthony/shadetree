require "test_helper"

# PLT-10: errors and alerts reach the log and the tracker hook with their context, minus
# anything personal; slow queries are logged without their literal values.
class ObservabilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FailingJob < ApplicationJob
    def perform(_client) = raise(ArgumentError, "No reply from maria@example.com or +1 (555) 010-0100")
  end

  setup do
    @reports = []
    Observability.tracker = ->(error, payload) { @reports << [ error, payload ] }
    @business = businesses(:one)
  end

  teardown { Observability.tracker = nil }

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io).tap { _1.level = :info }
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
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

    line = log[/\{"event":"error".*\}/]
    assert_equal [ "ObservabilityTest::FailingJob", payload[:job_id] ], JSON.parse(line).values_at("job_class", "job_id")
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

  test "scrubbing masks addresses, phone-like numbers and SQL literals" do
    assert_equal "to [EMAIL], tel [NUMBER], id 42", Observability.scrub("to a.b+c@mail.example.co, tel 555-010-0100, id 42")
    assert_equal "SELECT 1 WHERE email = '?' AND id = $1", Observability.scrub_sql("SELECT 1 WHERE email = 'o''neil@example.com'  AND id = $1")
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
