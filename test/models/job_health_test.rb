require "test_helper"

# PLT-10: failed jobs and a queue backlog raise an alert. Solid Queue's tables only exist where
# it runs, so these tests create them inside the test's transaction.
class JobHealthTest < ActiveSupport::TestCase
  include SolidQueueTables

  setup do
    @alerts = []
    Observability.tracker = ->(error, payload) { @alerts << payload if error.is_a?(Observability::Alert) }
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new # the watermark lives in the cache (null in test)
  end

  teardown do
    Observability.tracker = nil
    Rails.cache = @cache
  end

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

  test "new failures raise one alert naming their job classes, however late the check runs" do
    with_solid_queue_tables do
      fail_solid_queue_job("QuotePdfJob", at: 2.hours.ago) # before the first check: outside its look-back
      fail_solid_queue_job("VisitRemindersJob", at: 20.minutes.ago)
      JobHealth.check!

      alert = @alerts.sole
      assert_equal [ "Background jobs failed", 1, 2, %w[VisitRemindersJob] ], alert.values_at(:message, :new_failures, :failed, :failed_classes)
      assert_not JobHealth.current.healthy?

      @alerts.clear
      JobHealth.check!
      assert_empty @alerts # already alerted on

      fail_solid_queue_job("DataExportJob", at: 3.hours.ago) # a check that ran late still sees it
      fail_solid_queue_job("QuotePdfJob", at: 1.minute.ago)
      JobHealth.check!
      assert_empty @alerts # within JOB_ALERT_REPEAT_MINUTES of the last failure alert: still counting

      JobHealth.check!(now: 61.minutes.from_now)
      assert_equal [ 2, %w[DataExportJob QuotePdfJob] ], @alerts.sole.values_at(:new_failures, :failed_classes).then { [ _1, _2.sort ] }
    end
  end

  test "a long or slow queue raises a backlog alert" do
    config = Rails.configuration.x.observability
    with_solid_queue_tables do
      config.job_backlog_threshold = 1
      2.times { enqueue_solid_queue_job }
      JobHealth.check!
      assert_equal [ "Job queue backlog over threshold", 2 ], @alerts.sole.values_at(:message, :backlog)

      config.job_backlog_threshold = 100
      @alerts.clear
      JobHealth.check!(now: 11.minutes.from_now)
      assert_empty @alerts # still backlogged, but alerted on within JOB_ALERT_REPEAT_MINUTES

      JobHealth.check!(now: 61.minutes.from_now)
      assert_operator @alerts.sole[:oldest_wait_seconds], :>, 600
    end
  ensure
    config.job_backlog_threshold = 100
  end

  test "failures alert once JOB_FAILED_THRESHOLD of them are new, and keep counting until then" do
    config = Rails.configuration.x.observability
    with_solid_queue_tables do
      config.job_failed_threshold = 2
      fail_solid_queue_job("QuotePdfJob", at: 20.minutes.ago)
      JobHealth.check!
      assert_empty @alerts

      fail_solid_queue_job("VisitRemindersJob", at: 5.minutes.ago)
      JobHealth.check!
      assert_equal 2, @alerts.sole[:new_failures]
    end
  ensure
    config.job_failed_threshold = 1
  end

  test "a scheduled job nobody dispatched counts as waiting" do
    with_solid_queue_tables do
      SolidQueue::Job.create!(queue_name: "default", class_name: "QuotePdfJob", arguments: {}, scheduled_at: 1.minute.from_now)
      assert_equal 0, JobHealth.oldest_wait
      assert_operator JobHealth.oldest_wait(21.minutes.from_now), :>=, 20.minutes
    end
  end

  test "stale or untested backups raise a repeated alert, by /up/backup's rule (owner, 2026-11-22)" do
    config = Rails.configuration.x.observability
    dir = Dir.mktmpdir
    previous = ENV["BACKUP_STATUS_DIR"]
    ENV["BACKUP_STATUS_DIR"] = dir
    with_solid_queue_tables do
      JobHealth.check!
      assert_empty @alerts # off where backups don't run (BACKUP_ALERTS)

      config.backup_alerts = true
      JobHealth.check!
      assert_equal [ "Backups stale or untested", "stale" ], @alerts.sole.values_at(:message, :state)

      @alerts.clear
      FileUtils.touch(File.join(dir, "last_success"))
      JobHealth.check!(now: 30.minutes.from_now)
      assert_empty @alerts # now untested, but alerted on within JOB_ALERT_REPEAT_MINUTES

      JobHealth.check!(now: 61.minutes.from_now)
      assert_equal "untested", @alerts.sole[:state]

      @alerts.clear
      FileUtils.touch(File.join(dir, "last_drill"), mtime: 2.hours.from_now.to_time)
      JobHealth.check!(now: 2.hours.from_now)
      assert_empty @alerts
    end
  ensure
    config.backup_alerts = false
    ENV["BACKUP_STATUS_DIR"] = previous
    FileUtils.rm_rf(dir)
  end
end
