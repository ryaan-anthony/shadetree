require "test_helper"

# PLT-10: failed jobs and a queue backlog raise an alert. Solid Queue's tables only exist where
# it runs, so these tests create them inside the test's transaction.
class JobHealthTest < ActiveSupport::TestCase
  include SolidQueueTables

  setup do
    @alerts = []
    Observability.tracker = ->(error, payload) { @alerts << payload if error.is_a?(Observability::Alert) }
  end

  teardown { Observability.tracker = nil }

  test "without Solid Queue there is nothing to check" do
    assert_not JobHealth.available?
    assert_nil JobHealth.current
    assert_nil JobHealth.check!
  end

  test "a quiet queue is healthy and raises nothing" do
    with_solid_queue_tables do
      enqueue_solid_queue_job
      health = JobHealth.current
      assert health.healthy?
      assert_equal [ 0, 1 ], [ health.failed, health.backlog ]
      JobHealthCheckJob.perform_now
      assert_empty @alerts
    end
  end

  test "a recent failure raises an alert naming the job class" do
    with_solid_queue_tables do
      fail_solid_queue_job("QuotePdfJob", at: 2.hours.ago)
      fail_solid_queue_job("VisitRemindersJob")
      JobHealth.check!

      alert = @alerts.sole
      assert_equal [ "Background jobs failed", 1, 2 ], alert.values_at(:message, :recent_failures, :failed)
      assert_equal %w[QuotePdfJob VisitRemindersJob], alert[:failed_classes].sort
      assert_not JobHealth.current.healthy?
    end
  end

  test "a long or slow queue raises a backlog alert" do
    with_solid_queue_tables do
      ENV["JOB_BACKLOG_THRESHOLD"] = "1"
      2.times { enqueue_solid_queue_job }
      JobHealth.check!
      assert_equal [ "Job queue backlog over threshold", 2 ], @alerts.sole.values_at(:message, :backlog)

      ENV["JOB_BACKLOG_THRESHOLD"] = nil
      @alerts.clear
      JobHealth.check!(now: 11.minutes.from_now)
      assert_operator @alerts.sole[:oldest_wait_seconds], :>, 600
    end
  ensure
    ENV["JOB_BACKLOG_THRESHOLD"] = nil
  end
end
