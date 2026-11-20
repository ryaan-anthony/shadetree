# PLT-10: every 10 minutes (config/recurring.yml), alert on failed jobs and a queue backlog.
class JobHealthCheckJob < ApplicationJob
  queue_as :default

  def perform = JobHealth.check!
end
