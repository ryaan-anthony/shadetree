# JOB-04 / JOB-06: one member's day: the visits they're going on and the request follow-ups
# assigned to them, today first (in time order), then anything still open from earlier, then the
# days coming up. My day shows all of it; Home's "Your visits today" (#289) the first two.
#
# Each visit or follow-up is placed by the day on its own clock (CAT-07: a location may be in
# another zone), so "today" is today where the work is. A done follow-up stays (marked Done)
# until it's quoted or passed back. The same queries however many items there are.
class MyDay
  UPCOMING_DAYS = 14

  attr_reader :business, :user, :upcoming_days

  def initialize(business, user, upcoming_days: UPCOMING_DAYS)
    @business, @user, @upcoming_days = business, user, upcoming_days
  end

  def today = @today ||= in_time_order(items.select { |item, today| item.scheduled_on == today }.map(&:first))
  def earlier = @earlier ||= in_time_order(items.select { |item, today| item.scheduled_on < today && current?(item) }.map(&:first))

  # Day => items, for the days after today.
  def upcoming
    @upcoming ||= in_time_order(items.select { |item, today| item.scheduled_on > today && item.scheduled_on <= today + upcoming_days && current?(item) }.map(&:first))
                  .group_by(&:scheduled_on)
  end

  private

  # Every item with its own today. A day either side of the business's, for locations whose
  # today differs.
  def items
    @items ||= begin
      last = business.today + upcoming_days + 1
      recent = (business.today - 1)..last
      mine = Visit.joins(:assignments).where(visit_assignments: { user_id: user.id }).includes(:business, :assignees, job: [ { client: :contact_methods }, :property, :location ]) # JOB-12: the client's email
      # In order, like Home's team day (ActionDashboard#todays_visits): unordered, the rows come in
      # whatever order the table holds them, so the preloads' id lists (and whether Home's second
      # load of the same visits' assignments is answered from the query cache) varied by chance.
      visits = mine.open.where(scheduled_on: ..last).or(mine.where(scheduled_on: recent).where.not(status: "cancelled")).in_order.to_a
      follow_ups = RequestFollowUp.where(user_id: user.id, scheduled_on: ..last).includes(service_request: %i[client property location]).to_a
      (visits + follow_ups).each { _1.association(:business).target = business }
      (visits + follow_ups).map { [ _1, _1.time_zone.today ] }
    end
  end

  # A visit from earlier counts while it's open; a follow-up until it's quoted or passed back.
  def current?(item) = !item.is_a?(Visit) || item.open?

  # By day, timed ones by when they start, then the anytime ones.
  def in_time_order(items) = items.sort_by { [ _1.scheduled_on, _1.starts_at ? 0 : 1, _1.starts_at || Time.at(0), _1.is_a?(Visit) ? 0 : 1, _1.id ] }
end
