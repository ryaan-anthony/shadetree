# JOB-03: what the team calendar shows for a day or a week: the visits (filtered by member, or
# the ones nobody's on yet), where each sits on the time grid, the time the business is closed,
# a color per member, and the jobs still needing a visit. One query for the visits however
# many there are; a calendar week of 200 visits renders without any per-visit queries.
class ScheduleView
  HOUR_PX = 56
  DEFAULT_HOURS = 7..19
  COLORS = %w[sky violet amber rose teal lime indigo orange].freeze # tones in components.css (.cal-<color>)

  Placed = Data.define(:visit, :top, :height, :column, :columns)
  Shade = Data.define(:top, :height)

  attr_reader :business, :view, :date, :member, :color_by

  def initialize(business, view: "week", date: nil, member: nil, color_by: "member")
    @business = business
    @view = view == "day" ? "day" : "week"
    @date = date || business.today
    @member = member.presence
    @color_by = color_by == "status" ? "status" : "member"
  end

  # The days shown: one, or Monday to Sunday.
  def dates = @view == "day" ? [ @date ] : (@date.beginning_of_week..@date.end_of_week).to_a

  def previous_date = @date - (@view == "day" ? 1 : 7)
  def next_date = @date + (@view == "day" ? 1 : 7)
  def today? = dates.include?(business.today)

  def title
    return @date.strftime("%A, %B %-d") if @view == "day"

    first, last = dates.first, dates.last
    first.month == last.month ? "#{first.strftime("%B %-d")} – #{last.day}" : "#{first.strftime("%b %-d")} – #{last.strftime("%b %-d")}"
  end

  # Visits in the period (not cancelled), filtered, with what the grid needs loaded.
  def visits
    @visits ||= begin
      scope = Visit.where(scheduled_on: dates.first..dates.last).where.not(status: "cancelled")
                   .includes(:assignees, job: %i[client property]).in_order
      scope = scope.where.missing(:assignments) if @member == "unassigned"
      scope = scope.where(id: VisitAssignment.where(user_id: @member).select(:visit_id)) if @member && @member != "unassigned"
      scope.to_a
    end
  end

  def visits_on(date) = by_date.fetch(date, [])
  def anytime_on(date) = visits_on(date).select(&:anytime?)

  # The timed visits of a day, with their place on the grid. Visits that overlap share the
  # column's width side by side.
  def placed_on(date)
    timed = visits_on(date).reject(&:anytime?).sort_by { [ _1.starts_at, -_1.duration_minutes ] }
    groups = []
    timed.each do |visit|
      group = groups.last if groups.last && groups.last[:until] > visit.starts_at
      group ||= { visits: [], until: visit.starts_at }.tap { groups << _1 }
      group[:visits] << visit
      group[:until] = [ group[:until], visit.ends_at ].max
    end
    groups.flat_map do |group|
      lanes = []
      group[:visits].map do |visit|
        lane = lanes.index { _1 <= visit.starts_at } || lanes.size
        lanes[lane] = visit.ends_at
        [ visit, lane ]
      end.map { |visit, lane| Placed.new(visit:, top: px_for(visit.starts_at, date), height: [ px_between(visit.starts_at, visit.ends_at, date), 22 ].max, column: lane, columns: lanes.size) }
    end
  end

  # The hours the grid shows: the business's hours (or 7 am–7 pm), stretched to fit visits.
  def hours
    @hours ||= begin
      opens = dates.filter_map { |d| opening.day(d).periods.first&.begin&.then { hour_on(d, _1) } }
      closes = dates.filter_map { |d| opening.day(d).periods.last&.end&.then { hour_on(d, _1, round_up: true) } }
      timed = visits.reject(&:anytime?)
      from = [ *(opening.set? && opens.any? ? opens : [ DEFAULT_HOURS.first ]), *timed.map { hour_on(_1.scheduled_on, _1.starts_at) } ].min
      to = [ *(opening.set? && closes.any? ? closes : [ DEFAULT_HOURS.last ]), *timed.map { hour_on(_1.scheduled_on, _1.ends_at, round_up: true) } ].max
      from = from.clamp(0, 23)
      to = to.clamp(from + 1, 24)
      from...to
    end
  end

  def grid_height = hours.size * HOUR_PX

  # The closed parts of a day on the grid (outside its hours, and closures), for shading.
  def shades_on(date)
    return [] unless opening.set? || opening.closures_on(date).any?

    day = opening.day(date)
    start = business.local_time(date, format("%02d:00", hours.first))
    finish = hours.last == 24 ? midnight(date + 1) : business.local_time(date, format("%02d:00", hours.last))
    cursor = start
    shades = []
    day.periods.each do |period|
      shades << Shade.new(top: px_for(cursor, date), height: px_between(cursor, period.begin, date)) if period.begin > cursor
      cursor = [ cursor, period.end ].max
    end
    shades << Shade.new(top: px_for(cursor, date), height: px_between(cursor, finish, date)) if cursor < finish
    shades.select { _1.height.positive? }
  end

  def closures_on(date) = opening.closures_on(date)

  # Members who can be put on visits, with a color each and their booked hours this period.
  def members
    @members ||= business.business_users.active.includes(:user).map(&:user).sort_by { _1.full_name.downcase }
  end

  def color_for(user) = COLORS[members.index(user).to_i % COLORS.size]

  def visit_color(visit)
    return "status-#{visit.status.dasherize}" if @color_by == "status"

    first = visit.assignees.first
    first ? color_for(first) : "none"
  end

  def booked_hours
    @booked_hours ||= all_visits_in_period.each_with_object(Hash.new(0)) do |visit, hours|
      visit.assignments.each { hours[_1.user_id] += visit.duration_minutes / 60.0 }
    end
  end

  def unassigned_count = all_visits_in_period.count { _1.assignments.empty? }

  # Open jobs with no visit booked: the "Needs scheduling" panel.
  def unscheduled_jobs = Job.where(status: "unscheduled").includes(:client, :property).order(created_at: :desc).limit(20)

  private

  def by_date = @by_date ||= visits.group_by(&:scheduled_on)

  # Every visit in the period, unfiltered, for the member list's counts (ids and minutes only).
  def all_visits_in_period
    @all_visits_in_period ||= Visit.where(scheduled_on: dates.first..dates.last).where.not(status: "cancelled").includes(:assignments).to_a
  end

  def opening = @opening ||= OpeningHours.new(business)

  def midnight(date) = business.local_time(date, "00:00")

  # Wall-clock minutes into `date` (1440 for its next midnight), so a DST day still lines up
  # with the hour labels.
  def minutes_on(date, time)
    local = time.in_time_zone(business.time_zone)
    local.to_date > date ? 24 * 60 : (local.hour * 60) + local.min
  end

  def hour_on(date, time, round_up: false)
    hours = minutes_on(date, time) / 60.0
    round_up ? hours.ceil : hours.floor
  end

  # Pixels from the top of the grid for a time on the day being drawn.
  def px_for(time, date) = ((minutes_on(date, time) - (hours.first * 60)) * HOUR_PX / 60.0).round
  def px_between(from, to, date) = px_for(to, date) - px_for(from, date)
end
