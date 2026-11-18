module ScheduleHelper
  # The calendar's URL with some of its settings changed (period, view, member, colors).
  def schedule_link_params(schedule, **changes)
    { view: schedule.view, date: schedule.date.iso8601, member: schedule.member, color: (schedule.color_by if schedule.color_by == "status") }
      .merge(changes).compact_blank
  end

  def hour_label(hour) = hour.zero? || hour == 24 ? "12 am" : "#{((hour - 1) % 12) + 1} #{hour < 12 ? "am" : "pm"}"

  def crew_first_names(visit) = visit.assignees.any? ? visit.assignees.map(&:first_name).to_sentence : "Nobody yet"

  # "6 h", "1.5 h", "0.5 h": a short visit still shows up.
  def booked_hours_label(hours) = "#{hours.round(1).to_s.delete_suffix(".0")} h"
end
