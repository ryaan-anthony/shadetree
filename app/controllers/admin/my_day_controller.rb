# JOB-04: "My day": the visits the signed-in member is going on, today first (in time order),
# then anything still open from earlier, then the next two weeks. Technicians land here.
# JOB-06: requests they're following up sit among them, at their time (or with the anytime
# ones); a done one stays until they create the quote or pass it back.
#
# Each visit or follow-up is placed by the day on its own clock (CAT-07: a location may be in
# another zone), so "today" is today where the work is.
class Admin::MyDayController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :field_work

  UPCOMING_DAYS = 14

  def show
    # A day either side of the business's, for locations whose today differs.
    last = current_business.today + UPCOMING_DAYS + 1
    recent = (current_business.today - 1)..last
    mine = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id }).includes(:business, job: %i[client property location])
    visits = mine.open.where(scheduled_on: ..last).or(mine.where(scheduled_on: recent).where.not(status: "cancelled")).to_a
    follow_ups = RequestFollowUp.where(user_id: current_user.id, scheduled_on: ..last).includes(service_request: %i[client property location]).to_a
    (visits + follow_ups).each { _1.association(:business).target = current_business }
    items = (visits + follow_ups).map { [ _1, _1.time_zone.today ] }
    current = ->(item) { !item.is_a?(Visit) || item.open? }
    @today = in_time_order(items.select { |item, today| item.scheduled_on == today }.map(&:first))
    @earlier = in_time_order(items.select { |item, today| item.scheduled_on < today && current.(item) }.map(&:first))
    # QTE-07: drafts they made from requests given to them, until they're sent.
    @quote_drafts = (Quote.own_drafts_for(current_user).includes(:client).order(:created_at, :id).to_a if can?(:quote_requests) && !can?(:office))
    @upcoming = in_time_order(items.select { |item, today| item.scheduled_on > today && item.scheduled_on <= today + UPCOMING_DAYS && current.(item) }.map(&:first))
                .group_by(&:scheduled_on)
  end

  private

  # Visits and follow-ups by day, timed ones by when they start, then the anytime ones.
  def in_time_order(items) = items.sort_by { [ _1.scheduled_on, _1.starts_at ? 0 : 1, _1.starts_at || Time.at(0), _1.is_a?(Visit) ? 0 : 1, _1.id ] }
end
