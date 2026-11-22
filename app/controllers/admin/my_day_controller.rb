# JOB-04: "My day": the visits the signed-in member is going on, today first (in time order),
# then anything still open from earlier, then the next two weeks. Technicians land here.
# JOB-06: requests they're following up sit among them, at their time (or with the anytime
# ones); a done one stays until they create the quote or pass it back.
class Admin::MyDayController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :field_work

  UPCOMING_DAYS = 14

  def show
    today = current_business.today
    mine = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id }).includes(:business, job: %i[client property]).in_order
    follow_ups = RequestFollowUp.where(user_id: current_user.id, scheduled_on: ..(today + UPCOMING_DAYS))
                                .includes(service_request: %i[client property location]).to_a
    follow_ups.each { _1.association(:business).target = current_business }
    @today = in_time_order(mine.where(scheduled_on: today).where.not(status: "cancelled").to_a + follow_ups.select { _1.scheduled_on == today })
    @earlier = in_time_order(mine.open.where(scheduled_on: ...today).to_a + follow_ups.select { _1.scheduled_on < today })
    @upcoming = in_time_order(mine.open.where(scheduled_on: (today + 1)..(today + UPCOMING_DAYS)).to_a + follow_ups.select { _1.scheduled_on > today }).group_by(&:scheduled_on)
  end

  private

  # Visits and follow-ups by day, timed ones by their start, then the anytime ones.
  def in_time_order(items) = items.sort_by { [ _1.scheduled_on, _1.starts_at ? 0 : 1, _1.starts_at || Time.at(0), _1.is_a?(Visit) ? 0 : 1, _1.id ] }
end
