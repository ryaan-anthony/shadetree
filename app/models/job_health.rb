# PLT-10: is background work getting done? Failed jobs, and a queue that's too long or too slow,
# raise an alert (JobHealthCheckJob, every 10 minutes, through Observability.alert) and show on
# the operator console's home. Only where Solid Queue runs (staging and production); elsewhere
# jobs run in-process and there is no queue to look at.
#
# The check can't run when the workers are down, so /up/jobs (HealthController) answers 503 when
# the oldest due job has waited too long, for the external uptime check to watch.
#
# Thresholds (config/initializers/observability.rb): JOB_BACKLOG_THRESHOLD (jobs waiting,
# default 100) and JOB_WAIT_THRESHOLD (seconds the oldest due job has waited, default 600).
class JobHealth
  # The newest failure already alerted on. If the cache loses it, failures from the last hour count.
  WATERMARK_KEY = "job_health/last_failed_execution_id"
  FALLBACK_WINDOW = 1.hour

  attr_reader :failed, :new_failures, :new_failed_classes, :backlog, :oldest_wait, :newest_failure_id

  def self.available?
    defined?(SolidQueue::Job) && SolidQueue::Job.with_connection { _1.data_source_exists?(SolidQueue::Job.table_name) }
  rescue ActiveRecord::ActiveRecordError
    false
  end

  def self.current(now: Time.current, since_id: nil) = available? ? new(now:, since_id:) : nil

  # Run by JobHealthCheckJob: one alert per kind of problem, with counts and job classes only.
  # Failures alert once, however late or often the check runs.
  def self.check!(now: Time.current)
    health = current(now:, since_id: Rails.cache.read(WATERMARK_KEY)) or return
    health.alerts.each { |message, details| Observability.alert(message, **details) }
    Rails.cache.write(WATERMARK_KEY, health.newest_failure_id) if health.newest_failure_id
  end

  def self.backlog_threshold = Observability.config.job_backlog_threshold
  def self.wait_threshold = Observability.config.job_wait_threshold

  def initialize(now:, since_id: nil)
    failures = SolidQueue::FailedExecution.joins(:job)
    fresh = since_id ? failures.where("solid_queue_failed_executions.id > ?", since_id) : failures.where(created_at: (now - FALLBACK_WINDOW)..)
    @failed = failures.count
    @newest_failure_id = SolidQueue::FailedExecution.maximum(:id)
    @new_failures = fresh.count
    @new_failed_classes = fresh.group("solid_queue_jobs.class_name").order(count_all: :desc).limit(5).count
    @backlog = SolidQueue::ReadyExecution.count
    @oldest_wait = self.class.oldest_wait(now)
  end

  # Seconds the oldest due job has waited: ready jobs nobody picked up (workers down) and
  # scheduled ones not yet dispatched (dispatcher down). Two small queries, for /up/jobs too.
  def self.oldest_wait(now = Time.current)
    oldest = [ SolidQueue::ReadyExecution.minimum(:created_at),
               SolidQueue::ScheduledExecution.where(scheduled_at: ..now).minimum(:scheduled_at) ].compact.min
    oldest ? (now - oldest).to_i : 0
  end

  def stalled? = oldest_wait > self.class.wait_threshold
  def backlogged? = backlog > self.class.backlog_threshold || stalled?
  def healthy? = failed.zero? && !backlogged?

  # The most-failing job classes among every failure still waiting to be retried or discarded.
  def failed_classes
    SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.class_name").order(count_all: :desc).limit(5).count
  end

  # [message, details] pairs. Messages stay the same from run to run so a tracker groups them.
  def alerts
    list = []
    list << [ "Background jobs failed", { new_failures:, failed:, failed_classes: new_failed_classes.keys } ] if new_failures.positive?
    list << [ "Job queue backlog over threshold", { backlog:, oldest_wait_seconds: oldest_wait } ] if backlogged?
    list
  end
end
