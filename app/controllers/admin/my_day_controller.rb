# JOB-04: "My day": the visits the signed-in member is going on, today first (in time order),
# then anything still open from earlier, then the next two weeks. Technicians land here.
class Admin::MyDayController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :field_work

  UPCOMING_DAYS = 14

  def show
    today = current_business.today
    mine = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id }).includes(:business, job: %i[client property]).in_order
    @today = mine.where(scheduled_on: today).where.not(status: "cancelled").to_a
    @earlier = mine.open.where(scheduled_on: ...today).to_a
    @upcoming = mine.open.where(scheduled_on: (today + 1)..(today + UPCOMING_DAYS)).to_a.group_by(&:scheduled_on)
  end
end
