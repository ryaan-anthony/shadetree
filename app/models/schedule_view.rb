# JOB-03: what the team calendar shows for a day or a week: the visits (filtered by member, or
# the ones nobody's on yet), where each sits on the time grid, the time the business is closed,
# a color per member, and the jobs still needing a visit. One query for the visits however
# many there are; a calendar week of 200 visits renders without any per-visit queries.
#
# JOB-07: request follow-ups (RequestFollowUp) sit on the grid with the visits, for people who
# can see requests (follow_ups: true): "items" are both, placed and colored the same way.
class ScheduleView
  HOUR_PX = 56
  MIN_PX = 22 # the shortest a visit is drawn, so its first line can be read
  DEFAULT_HOURS = 7..19
  COLORS = %w[sky violet amber rose teal lime indigo orange].freeze # tones in components.css (.cal-<color>)

  Placed = Data.define(:visit, :top, :height, :column, :columns)
  # One column of the grid: a day (week view), or one person's day (day view for everyone).
  # `member` is a user, :none for "Nobody yet", or nil for everyone.
  Column = Data.define(:date, :member) do
    def member_key = member == :none ? "none" : member&.id&.to_s
  end
  Shade = Data.define(:top, :height)

  attr_reader :business, :view, :date, :member, :color_by

  def initialize(business, view: "week", date: nil, member: nil, color_by: "member", location: nil, follow_ups: false)
    @location = location # CAT-07: shades that location's hours (else the main location's)
    @show_follow_ups = follow_ups
    @business = business
    @view = view == "day" ? "day" : "week"
    @date = date || place.today # the filtered location's today (CAT-07)
    @member = member.presence
    @color_by = color_by == "status" ? "status" : "member"
  end

  # The days shown: one, or Monday to Sunday.
  def dates = @view == "day" ? [ @date ] : (@date.beginning_of_week..@date.end_of_week).to_a

  def previous_date = @date - (@view == "day" ? 1 : 7)
  def next_date = @date + (@view == "day" ? 1 : 7)
  def today? = dates.include?(place.today)

  # The period, always with its year (QA #274): "November 23 – 29, 2026", "Monday, November 23, 2026".
  def title
    return @date.strftime("%A, %B %-d, %Y") if @view == "day"

    first, last = dates.first, dates.last
    return "#{first.strftime("%b %-d")}#{", #{first.year}" if first.year != last.year} – #{last.strftime("%b %-d, %Y")}" unless first.month == last.month

    "#{first.strftime("%B %-d")} – #{last.day}, #{last.year}"
  end

  # The grid's clock named for people: "Eastern Time (US & Canada)".
  def zone_name
    zone = place.time_zone
    ActiveSupport::TimeZone::MAPPING.key(zone.tzinfo.identifier) || zone.tzinfo.identifier.split("/").last.tr("_", " ")
  end

  # The days a visit can still be booked on from the grid (today on), for its "New visit" slots.
  def bookable?(date) = date >= place.today

  # Visits in the period (not cancelled), filtered, with what the grid needs loaded.
  def visits
    @visits ||= begin
      scope = Visit.where(scheduled_on: dates.first..dates.last).where.not(status: "cancelled")
                   .includes(:assignees, job: %i[client property location]).in_order
      scope = scope.where.missing(:assignments) if @member == "unassigned"
      scope = scope.where(id: VisitAssignment.where(user_id: @member).select(:visit_id)) if @member && @member != "unassigned"
      scope.to_a.each { _1.association(:business).target = business } # labels need its time zone; not one query per visit
    end
  end

  # JOB-07: the follow-ups in the period (one person's, or none for "Not assigned": a follow-up
  # always has someone), at the filtered location when there is one.
  def follow_ups
    @follow_ups ||= if @show_follow_ups && @member != "unassigned"
      scope = RequestFollowUp.where(scheduled_on: dates.first..dates.last).includes(:user, service_request: %i[client property location])
      scope = scope.where(user_id: @member) if @member
      scope = scope.where(service_request_id: ServiceRequest.where(location_id: @location.id).select(:id)) if @location
      scope.to_a.each { _1.association(:business).target = business }
    else
      []
    end
  end

  # JOB-07, for #289's "Next visit" hint on an empty period: the next follow-up booked after it,
  # for the same person (none for "Not assigned") at the filtered location, when follow-ups are shown. The hint takes the
  # earlier of this and the next visit.
  def next_follow_up_after
    return if !@show_follow_ups || @member == "unassigned" || items.any?
    return @next_follow_up_after if defined?(@next_follow_up_after)

    scope = RequestFollowUp.where(scheduled_on: [ dates.last + 1, place.today ].max.., done_at: nil)
    scope = scope.where(user_id: @member) if @member
    scope = scope.where(service_request_id: ServiceRequest.where(location_id: @location.id).select(:id)) if @location
    @next_follow_up_after = scope.order(:scheduled_on, Arel.sql("starts_at NULLS LAST"), :id).first
  end

  # Visits and follow-ups together, in time order.
  def items = @items ||= (visits + follow_ups).sort_by { [ _1.scheduled_on, _1.starts_at ? 0 : 1, _1.starts_at || Time.at(0), _1.is_a?(Visit) ? 0 : 1, _1.id ] }

  # What's on a day: visits and follow-ups.
  def visits_on(date) = by_date.fetch(date, [])

  # The grid's columns. A day for everyone is split by person, so a visit can be dragged from
  # one person to another; a visit with two people going shows in both their columns.
  def columns
    @columns ||= if @view == "day" && @member.nil?
      # Also anyone still on a visit that day who has left the team, so their work isn't hidden.
      others = visits_on(@date).flat_map(&:assignees).uniq - members
      [ *members.map { Column.new(@date, _1) }, *others.sort_by { _1.full_name.downcase }.map { Column.new(@date, _1) }, Column.new(@date, :none) ]
    else
      dates.map { Column.new(_1, nil) }
    end
  end

  def by_person? = columns.first.member.present?

  def visits_in(column)
    visits = visits_on(column.date)
    case column.member
    when nil then visits
    when :none then visits.select { _1.assignees.empty? }
    else visits.select { |visit| visit.assignees.include?(column.member) }
    end
  end

  def anytime_in(column) = visits_in(column).select(&:anytime?)

  # The timed visits of a day, with their place on the grid. Visits that overlap share the
  # column's width side by side.
  def placed_in(column)
    date = column.date
    timed = visits_in(column).reject(&:anytime?).sort_by { [ _1.starts_at, -_1.duration_minutes ] }
    groups = []
    # Where each visit's drawn block ends: a short one is drawn MIN_PX tall, so it can cover the next.
    drawn_end = ->(visit) { [ visit.ends_at, visit.starts_at + (MIN_PX * 60.0 / HOUR_PX).ceil.minutes ].max }
    timed.each do |visit|
      group = groups.last if groups.last && groups.last[:until] > visit.starts_at
      group ||= { visits: [], until: visit.starts_at }.tap { groups << _1 }
      group[:visits] << visit
      group[:until] = [ group[:until], drawn_end.(visit) ].max
    end
    groups.flat_map do |group|
      lanes = []
      group[:visits].map do |visit|
        lane = lanes.index { _1 <= visit.starts_at } || lanes.size
        lanes[lane] = drawn_end.(visit)
        [ visit, lane ]
      end.map { |visit, lane| Placed.new(visit:, top: px_for(visit.starts_at, date), height: [ px_between(visit.starts_at, visit.ends_at, date), MIN_PX ].max, column: lane, columns: lanes.size) }
    end
  end

  # The hours the grid shows: the business's opening hours (or 7 am–7 pm), stretched to fit
  # visits. From the weekly hours, not what's left after closures, so a closure is shaded on the
  # grid rather than cut off it.
  def hours
    @hours ||= begin
      weekly = dates.filter_map { opening.day(_1).hours }
      opens = weekly.map { clock_hour(_1[0]) }
      closes = weekly.map { |(open, close)| WeeklyHours.end_of_day?(close) || close <= open ? 24 : clock_hour(close, round_up: true) }
      timed = items.reject(&:anytime?)
      from = [ *(opens.any? ? opens : [ DEFAULT_HOURS.first ]), *timed.map { hour_on(_1.scheduled_on, _1.starts_at) } ].min
      to = [ *(closes.any? ? closes : [ DEFAULT_HOURS.last ]), *timed.map { hour_on(_1.scheduled_on, _1.ends_at, round_up: true) } ].max
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
    start = place.local_time(date, format("%02d:00", hours.first))
    finish = hours.last == 24 ? midnight(date + 1) : place.local_time(date, format("%02d:00", hours.last))
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
    @members ||= begin
      users = business.business_users.active.includes(:user).map(&:user)
      # CAT-07: filtered to a location with a team, just that team.
      team = @location ? Tenancy.with_business(business) { LocationMember.where(location: @location).pluck(:user_id) } : []
      users = users.select { team.include?(_1.id) } if team.any?
      users.sort_by { _1.full_name.downcase }
    end
  end

  def color_for(user)
    index = members.index(user)
    index ? COLORS[index % COLORS.size] : "none" # someone no longer on the team
  end

  # JOB-07: a follow-up is colored like a visit (its person's, or scheduled / done by status).
  def visit_color(visit)
    return "status-#{visit.status.dasherize}" if @color_by == "status"

    first = visit.assignees.first
    first ? color_for(first) : "none"
  end

  # Hours booked per person this period: visits, and follow-ups when they're shown (JOB-07).
  def booked_hours
    @booked_hours ||= all_visits_in_period.each_with_object(Hash.new(0)) do |visit, hours|
      visit.assignments.each { hours[_1.user_id] += visit.duration_minutes / 60.0 }
    end.tap do |hours|
      next unless @show_follow_ups

      scope = RequestFollowUp.where(scheduled_on: dates.first..dates.last)
      scope = scope.where(service_request_id: ServiceRequest.where(location_id: @location.id).select(:id)) if @location # as follow_ups is
      scope.pluck(:user_id, :duration_minutes).each { |user_id, minutes| hours[user_id] += minutes / 60.0 }
    end
  end

  def unassigned_count = all_visits_in_period.count { _1.assignments.empty? }

  # Open jobs with no visit booked: the "Needs scheduling" panel.
  UNSCHEDULED_SHOWN = 20
  def unscheduled_jobs = Job.where(status: "unscheduled").includes(:client, :property).order(:created_at, :id).limit(UNSCHEDULED_SHOWN)
  def unscheduled_count = @unscheduled_count ||= Job.where(status: "unscheduled").count

  # The grid's clock: the filtered location's time zone (CAT-07), else the business's.
  def place = @location || business

  private

  def by_date = @by_date ||= items.group_by(&:scheduled_on)

  # Every visit in the period, unfiltered, for the member list's counts (ids and minutes only).
  def all_visits_in_period
    @all_visits_in_period ||= Visit.where(scheduled_on: dates.first..dates.last).where.not(status: "cancelled").includes(:assignments).to_a
  end

  def opening = @opening ||= OpeningHours.new(place)


  def midnight(date) = place.local_time(date, "00:00")

  def clock_hour(clock, round_up: false)
    hour, minute = clock.split(":").map(&:to_i)
    round_up && minute.positive? ? hour + 1 : hour
  end

  # Wall-clock minutes into `date` (1440 for its next midnight), so a DST day still lines up
  # with the hour labels.
  def minutes_on(date, time)
    local = time.in_time_zone(place.time_zone)
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
