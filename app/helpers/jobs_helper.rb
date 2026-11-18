module JobsHelper
  JOB_STATUS_TONES = { "unscheduled" => :warning, "scheduled" => :info, "in_progress" => :info,
                       "completed" => :success, "cancelled" => :neutral }.freeze

  def job_status_badge(job) = badge(job.status_label, tone: JOB_STATUS_TONES.fetch(job.status))
end
