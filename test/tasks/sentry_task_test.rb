require "test_helper"
require "rake"

# PLT-10: bin/rails sentry:test refuses to run while Sentry is off (no SENTRY_DSN).
class SentryTaskTest < ActiveSupport::TestCase
  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("sentry:test") }

  test "stops without a DSN and sends nothing" do
    previous = ENV.delete("SENTRY_DSN")
    Rake::Task["sentry:test"].reenable
    _, err = capture_io { assert_raises(SystemExit) { Rake::Task["sentry:test"].invoke } }
    assert_match "SENTRY_DSN is not set", err
  ensure
    ENV["SENTRY_DSN"] = previous if previous
  end
end
