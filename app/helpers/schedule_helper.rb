module ScheduleHelper
  # The calendar's URL with some of its settings changed (period, view, member, colors).
  def schedule_link_params(schedule, **changes)
    { view: schedule.view, date: schedule.date.iso8601, member: schedule.member, color: (schedule.color_by if schedule.color_by == "status") }
      .merge(changes).compact_blank
  end

  def hour_label(hour) = hour.zero? || hour == 24 ? "12 am" : "#{((hour - 1) % 12) + 1} #{hour < 12 ? "am" : "pm"}"

  def crew_first_names(visit) = visit.assignees.any? ? visit.assignees.map { _1.first_name.presence || _1.full_name }.to_sentence : "Not assigned"

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

  # JOB-07: the same for a request follow-up (open ones), moved through its own address.
  def schedule_follow_up_drag_data(follow_up, column)
    return {} unless follow_up.open?

    start = @schedule ? follow_up.start_time_in(@schedule.place.time_zone).to_s : follow_up.start_time.to_s
    { schedule_drag_target: "visit", visit: follow_up.service_request.uid, lock: follow_up.lock_version, start:, timing: follow_up.timing, member: column.member_key,
      move_url: admin_schedule_follow_up_move_path(follow_up.service_request), label: "#{follow_up.service_request.client.display_name}, #{follow_up.time_label}" }
  end

  # CAT-07: a visit's time, with its zone named when it isn't the calendar's ("9 am CST").
  def schedule_time_label(visit, schedule)
    label = visit.time_label.delete_prefix("Arrive ")
    zone = visit.time_zone
    return label if visit.anytime? || zone.tzinfo.identifier == schedule.place.time_zone.tzinfo.identifier

    "#{label} #{visit.starts_at.in_time_zone(zone).strftime("%Z")}"
  end

  # JOB-08: what screen readers hear for a Busy block: "Busy, 2 to 3 pm, Marcus", "Busy,
  # arriving 2 to 4 pm CST, Marcus", "Busy, anytime, Marcus"; on the grid with its day, as a
  # visit's is (", Monday, November 23").
  def schedule_busy_label(busy, schedule, day: false)
    zone = (" #{busy.starts_at.in_time_zone(busy.time_zone).strftime("%Z")}" unless busy.anytime? || busy.time_zone.tzinfo.identifier == schedule.place.time_zone.tzinfo.identifier)
    "Busy, #{busy.spoken_time}#{zone}, #{busy_name(busy.user)}#{", #{busy.scheduled_on.strftime("%A, %B %-d")}" if day}"
  end

  def busy_name(user) = user.first_name.presence || user.full_name

  # A grid column's name for screen readers: its day, and whose it is in a day split by person.
  def schedule_column_label(column)
    [ column.date.strftime("%A, %B %-d"), (column.member == :none ? "Not assigned" : column.member&.full_name) ].compact.join(", ")
  end

  # QA #274: an empty hour on the grid, as a link to a new visit then (and with that person).
  # JOB-08: and who's Busy then, since a Busy block can't be focused ("…, Marcus busy").
  def schedule_slot_label(column, hour, busy: [])
    who = column.member.respond_to?(:full_name) ? ", with #{column.member.full_name}" : ""
    then_busy = busy.any? ? ", #{busy.map { busy_name(_1) }.to_sentence} busy" : ""
    "New visit, #{column.date.strftime("%A, %B %-d")}, #{format("%d:00 %s", ((hour - 1) % 12) + 1, hour < 12 ? "AM" : "PM")}#{who}#{then_busy}"
  end

  # The slot's day, time and person (?crew=, or the person the calendar is filtered to), what the
  # calendar shows (view, filter) and the slot itself, to focus again on coming back.
  def schedule_slot_params(column, hour, schedule)
    crew = column.member.respond_to?(:id) ? column.member.id : (schedule.member unless schedule.member == "unassigned")
    { on: column.date.iso8601, at: format("%02d:00", hour), crew:, view: schedule.view, member: schedule.member, slot: schedule_slot_key(column, hour) }.compact_blank
  end

  # A slot's focus key: "slot-2026-11-24-09-all" (its day, hour and column's person).
  def schedule_slot_key(column, hour) = "slot-#{column.date.iso8601}-#{format("%02d", hour)}-#{column.member_key.presence || "all"}"

  # PLT-17: a visit that's started or done says so in words, so its status colour isn't the
  # only sign of it (" · In progress").
  def schedule_status_words(visit) = visit.status == "scheduled" ? "" : " · #{StatusHelper::MAP[:visit].fetch(visit.status).last}"
end
