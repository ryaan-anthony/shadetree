module JobsHelper
  JOB_STATUS_TONES = { "unscheduled" => :warning, "scheduled" => :info, "in_progress" => :info,
                       "completed" => :success, "cancelled" => :neutral }.freeze

  def job_status_badge(job) = badge(job.status_label, tone: JOB_STATUS_TONES.fetch(job.status))

  # JOB-02: one line of a visit's history.
  def visit_event_text(event)
    data = event.data
    case event.kind
    when "scheduled" then "Scheduled"
    when "rescheduled" then "Moved from #{data.dig("from", "when") || data["from"]} to #{data.dig("to", "when") || data["to"]}"
    when "reassigned"
      [ ("Added #{data["added"].to_sentence}" if data["added"].present?), ("removed #{data["removed"].to_sentence}" if data["removed"].present?) ].compact.join(", ").upcase_first
    when "updated" then "Changed the #{data["changed"].map { { "duration_minutes" => "duration", "instructions" => "instructions" }.fetch(_1, _1) }.to_sentence}"
    when "cancelled" then data["reason"] ? "Cancelled: “#{data["reason"]}”" : "Cancelled"
    else event.kind.humanize
    end
  end
end
