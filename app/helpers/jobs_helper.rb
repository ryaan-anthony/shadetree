module JobsHelper
  JOB_STATUS_TONES = { "unscheduled" => :warning, "scheduled" => :info, "in_progress" => :info,
                       "completed" => :success, "cancelled" => :neutral }.freeze

  def job_status_badge(job) = badge(job.status_label, tone: JOB_STATUS_TONES.fetch(job.status))

  # CAT-07: " MST" after a time on My day when the work is in another zone than the business's
  # (My day names the business's zone once at the top).
  def other_zone_label(item)
    return if item.starts_at.nil? || item.time_zone.tzinfo == current_business.time_zone.tzinfo

    tag.span(" #{item.starts_at.in_time_zone(item.time_zone).strftime("%Z")}", class: "font-normal text-muted")
  end

  # Home's own day (#289, JOB-06): "2 visits", "1 visit and 1 request follow-up", "1 request
  # follow-up", or "Nothing today".
  def day_items_count(items)
    return "Nothing today" if items.empty?

    follow_ups = items.count { !_1.is_a?(Visit) }
    visits = items.size - follow_ups
    parts = [ (pluralize(visits, "visit") if visits.positive? || follow_ups.zero?), (pluralize(follow_ups, "request follow-up") if follow_ups.positive?) ]
    parts.compact.to_sentence
  end

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
