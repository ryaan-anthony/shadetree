# PLT-10: /up/jobs, for the external uptime check. 503 when the oldest due background job has
# waited longer than JOB_WAIT_THRESHOLD (workers or dispatcher down, or hopelessly behind): the
# one failure JobHealthCheckJob can't report, since it runs on those workers. /up stays the
# cheap boot check the deploy uses. Says only "ok" or "stalled"; no counts or job names.
class HealthController < ActionController::Base
  def jobs
    stalled = JobHealth.available? && JobHealth.oldest_wait > JobHealth.wait_threshold
    render plain: stalled ? "stalled" : "ok", status: stalled ? :service_unavailable : :ok
  end
end
