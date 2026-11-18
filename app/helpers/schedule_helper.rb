module ScheduleHelper
  # The calendar's URL with some of its settings changed (period, view, member, colors).
  def schedule_link_params(schedule, **changes)
    { view: schedule.view, date: schedule.date.iso8601, member: schedule.member, color: (schedule.color_by if schedule.color_by == "status") }
      .merge(changes).compact_blank
  end

  def hour_label(hour) = hour.zero? || hour == 24 ? "12 am" : "#{((hour - 1) % 12) + 1} #{hour < 12 ? "am" : "pm"}"
end
