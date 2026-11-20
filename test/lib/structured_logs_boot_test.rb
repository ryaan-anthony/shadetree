require "test_helper"
require "open3"

# PLT-10: with STRUCTURED_LOGS on at boot, as in production, Rails' text log subscribers are
# detached, its exception dump drops to debug and every line is JSON. Checked in a fresh process,
# since detaching subscribers here would change every other test's logging.
class StructuredLogsBootTest < ActiveSupport::TestCase
  SCRIPT = <<~RUBY
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io, level: :info, formatter: Rails.logger.broadcasts.first.formatter.class.new)
    Rails.logger.broadcast_to(ActiveSupport::TaggedLogging.new(logger))
    ActionController::Base; ActionView::Base; ActiveJob::Base; ActionMailer::Base # run the on_load hooks
    Rails.application.call(Rack::MockRequest.env_for("http://www.example.com/no-such-page")).last.close # the line is written on close
    Rails.logger.info("a plain line")
    puts({ subscribers: ActiveSupport::LogSubscriber.log_subscribers.map { _1.class.name },
           level: Rails.application.env_config["action_dispatch.debug_exception_log_level"],
           lines: io.string.lines }.to_json)
  RUBY

  test "production-style boot: no text subscribers, debug-level exception dumps, JSON lines only" do
    env = { "STRUCTURED_LOGS" => "true", "RAILS_ENV" => "test", "COVERAGE" => "false" }
    output, status = Open3.capture2e(env, Rails.root.join("bin/rails").to_s, "runner", SCRIPT, chdir: Rails.root.to_s)
    assert status.success?, output
    result = JSON.parse(output.lines.last)

    assert_empty result["subscribers"] & %w[ActionController::LogSubscriber ActionView::LogSubscriber ActiveJob::LogSubscriber ActionMailer::LogSubscriber]
    assert_equal Logger::DEBUG, result["level"]
    lines = result["lines"].map { JSON.parse(_1) }
    request = lines.find { _1["event"] == "request" }
    assert request, result["lines"].join
    assert_equal [ 404, "/no-such-page" ], request.values_at("status", "path")
    assert_includes lines.map { _1["message"] }, "a plain line"
  end
end
