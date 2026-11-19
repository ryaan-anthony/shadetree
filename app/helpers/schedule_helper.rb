module ScheduleHelper
  # The calendar's URL with some of its settings changed (period, view, member, colors).
  def schedule_link_params(schedule, **changes)
    { view: schedule.view, date: schedule.date.iso8601, member: schedule.member, color: (schedule.color_by if schedule.color_by == "status") }
      .merge(changes).compact_blank
  end

  def hour_label(hour) = hour.zero? || hour == 24 ? "12 am" : "#{((hour - 1) % 12) + 1} #{hour < 12 ? "am" : "pm"}"

  def crew_first_names(visit) = visit.assignees.any? ? visit.assignees.map { _1.first_name.presence || _1.full_name }.to_sentence : "Nobody yet"

  # "6 h", "1.5 h", "0.5 h": a short visit still shows up.
  def booked_hours_label(hours) = "#{hours.round(1).to_s.delete_suffix(".0")} h"

  # A visit's id on the grid; in a day split by person it can show in more than one column.
  def schedule_visit_id(visit, column, schedule)
    schedule.by_person? ? "cal-visit-#{visit.uid}-#{column.member_key}" : "cal-visit-#{visit.uid}"
  end

  # What dragging a visit needs to know about it (only open visits can be moved).
  def schedule_drag_data(visit, column)
    return {} unless visit.open?

    # CAT-07: the start on the calendar's clock, which a drag's time is on too.
    start = @schedule ? visit.start_time_in(@schedule.place.time_zone).to_s : visit.start_time.to_s
    { schedule_drag_target: "visit", visit: visit.uid, lock: visit.lock_version, start:,
      timing: visit.timing, member: column.member_key, label: "#{visit.job.client.display_name}, #{visit.time_label}" }
  end

  # CAT-07: a visit's time, with its zone named when it isn't the calendar's ("9 am CST").
  def schedule_time_label(visit, schedule)
    label = visit.time_label.delete_prefix("Arrive ")
    zone = visit.time_zone
    return label if visit.anytime? || zone.tzinfo.identifier == schedule.place.time_zone.tzinfo.identifier

    "#{label} #{visit.starts_at.in_time_zone(zone).strftime("%Z")}"
  end

  # A grid column's name for screen readers: its day, and whose it is in a day split by person.
  def schedule_column_label(column)
    [ column.date.strftime("%A, %B %-d"), (column.member == :none ? "Nobody yet" : column.member&.full_name) ].compact.join(", ")
  end
end
