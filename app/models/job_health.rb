# PLT-10: is background work getting done? Failed jobs, and a queue that's too long or too slow,
# raise an alert (JobHealthCheckJob, every 10 minutes, through Observability.alert) and show on
# the operator console's home. Only where Solid Queue runs (staging and production); elsewhere
# jobs run in-process and there is no queue to look at.
#
# Thresholds: JOB_BACKLOG_THRESHOLD (jobs waiting, default 100) and JOB_WAIT_THRESHOLD (seconds
# the oldest job has waited, default 600).
class JobHealth
  CHECK_EVERY = 10.minutes

  attr_reader :failed, :recent_failures, :failed_classes, :backlog, :oldest_wait

  def self.available?
    defined?(SolidQueue::Job) && SolidQueue::Job.with_connection { _1.data_source_exists?(SolidQueue::Job.table_name) }
  rescue ActiveRecord::ActiveRecordError
    false
  end

  def self.current(now: Time.current) = available? ? new(now:) : nil

  # Run by JobHealthCheckJob: one alert per kind of problem, with counts and job classes only.
  def self.check!(now: Time.current)
    current(now:)&.alerts&.each { |message, details| Observability.alert(message, **details) }
  end

  def self.backlog_threshold = Integer(ENV.fetch("JOB_BACKLOG_THRESHOLD", 100))
  def self.wait_threshold = Integer(ENV.fetch("JOB_WAIT_THRESHOLD", 600))

  def initialize(now:)
    failures = SolidQueue::FailedExecution.joins(:job)
    @failed = failures.count
    @recent_failures = failures.where(created_at: (now - CHECK_EVERY)..).count
    @failed_classes = failures.group("solid_queue_jobs.class_name").order(count_all: :desc).limit(5).count
    @backlog = SolidQueue::ReadyExecution.count
    oldest = SolidQueue::ReadyExecution.minimum(:created_at)
    @oldest_wait = oldest ? (now - oldest).to_i : 0
  end

  def backlogged? = backlog > self.class.backlog_threshold || oldest_wait > self.class.wait_threshold
  def healthy? = failed.zero? && !backlogged?

  # [message, details] pairs. Messages stay the same from run to run so a tracker groups them.
  def alerts
    list = []
    list << [ "Background jobs failed", { recent_failures:, failed:, failed_classes: failed_classes.keys } ] if recent_failures.positive?
    list << [ "Job queue backlog over threshold", { backlog:, oldest_wait_seconds: oldest_wait } ] if backlogged?
    list
  end
end
