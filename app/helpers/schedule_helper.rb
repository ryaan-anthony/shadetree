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

  # A visit's id on the grid; in a day split by person it can show in more than one column.
  def schedule_visit_id(visit, column, schedule)
    schedule.by_person? ? "cal-visit-#{visit.uid}-#{column.member_key}" : "cal-visit-#{visit.uid}"
  end

  # What dragging a visit needs to know about it (only open visits can be moved).
  def schedule_drag_data(visit, column)
    return {} unless visit.open?

    { schedule_drag_target: "visit", visit: visit.uid, lock: visit.lock_version, start: visit.start_time.to_s,
      timing: visit.timing, member: column.member_key, label: "#{visit.job.client.display_name}, #{visit.time_label}" }
  end

  # A grid column's name for screen readers: its day, and whose it is in a day split by person.
  def schedule_column_label(column)
    [ column.date.strftime("%A, %B %-d"), (column.member == :none ? "Nobody yet" : column.member&.full_name) ].compact.join(", ")
  end
end
