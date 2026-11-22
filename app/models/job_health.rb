# PLT-10: is background work getting done? Failed jobs, and a queue that's too long or too slow,
# raise an alert (JobHealthCheckJob, every 10 minutes, through Observability.alert) and show on
# the operator console's home. Only where Solid Queue runs (staging and production); elsewhere
# jobs run in-process and there is no queue to look at.
#
# The check can't run when the workers are down, so /up/jobs (HealthController) answers 503 when
# the oldest due job has waited too long, for the external uptime check to watch.
#
# Thresholds (config/initializers/observability.rb): JOB_BACKLOG_THRESHOLD (jobs waiting,
# default 100), JOB_WAIT_THRESHOLD (seconds the oldest due job has waited, default 600),
# JOB_FAILED_THRESHOLD (new failures that raise an alert, default 1) and JOB_ALERT_REPEAT_MINUTES
# (how often a backlog that persists is alerted again, default 60, to stay within Sentry's quota).
# Each check also checks in with Sentry Cron (the "job-health" monitor, ADR 0027): error while a
# problem lasts, ok after, and Sentry flags a missed check-in when the check itself stopped.
#
# Backups too (owner, 2026-11-22): where they're expected (BACKUP_ALERTS, on in staging and
# production), BackupStatus's rule for /up/backup (no backup within BACKUP_MAX_AGE_HOURS, or no
# passing restore drill since) raises an alert, repeated like the backlog, and fails the check-in.
class JobHealth
  # The newest failure already alerted on. If the cache loses it, failures from the last hour count.
  WATERMARK_KEY = "job_health/last_failed_execution_id"
  FALLBACK_WINDOW = 1.hour
  MONITOR = "job-health"
  EVERY_MINUTES = 10 # config/recurring.yml
  FAILED = "Background jobs failed"
  BACKLOG = "Job queue backlog over threshold"
  BACKUPS = "Backups stale or untested"
  REPEATED = [ BACKLOG, BACKUPS ].freeze # alerted again at most every JOB_ALERT_REPEAT_MINUTES while they last

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
    alerts = health.alerts + backup_alerts(now)
    Observability.tracker.check_in(MONITOR, alerts.any? ? :error : :ok, every_minutes: EVERY_MINUTES) if Observability.tracker.respond_to?(:check_in)
    alerts.reject! { |message, _| REPEATED.include?(message) && !repeat_due?(message, now) }
    alerts.each { |message, details| Observability.alert(message, **details) }
    # Failures below the threshold keep counting towards it; alerted ones aren't counted again.
    Rails.cache.write(WATERMARK_KEY, health.newest_failure_id) if health.newest_failure_id && !health.failures_pending?
    alerts.each { |message, _| Rails.cache.write(alerted_key(message), now) if REPEATED.include?(message) }
  end

  # The same rule as /up/backup, where nightly backups run.
  def self.backup_alerts(now)
    return [] unless Observability.config.backup_alerts

    state = BackupStatus.state(now:)
    state == "ok" ? [] : [ [ BACKUPS, { state: } ] ]
  end

  def self.repeat_due?(message, now)
    last = Rails.cache.read(alerted_key(message))
    last.nil? || last <= now - Observability.config.job_alert_repeat_minutes.minutes
  end

  def self.alerted_key(message) = "job_health/alerted_at/#{message.parameterize}"

  def self.failed_threshold = [ Observability.config.job_failed_threshold, 1 ].max

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
  def failures_alerted? = new_failures >= self.class.failed_threshold
  def failures_pending? = new_failures.positive? && !failures_alerted?

  # The most-failing job classes among every failure still waiting to be retried or discarded.
  def failed_classes
    SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.class_name").order(count_all: :desc).limit(5).count
  end

  # [message, details] pairs. Messages stay the same from run to run so a tracker groups them.
  def alerts
    list = []
    list << [ FAILED, { new_failures:, failed:, failed_classes: new_failed_classes.keys } ] if failures_alerted?
    list << [ BACKLOG, { backlog:, oldest_wait_seconds: oldest_wait } ] if backlogged?
    list
  end
end
