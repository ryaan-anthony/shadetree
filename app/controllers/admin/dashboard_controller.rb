class Admin::DashboardController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  allow_any_member
  filters_by_location ServiceRequest, Quote, Job, Invoice, Visit, Payment, QuoteResponse, only: :index # CAT-07

  # Members who don't work in the office land on the first page they can use: their day view
  # (technicians, JOB-04), else the schedule or the team (custom roles, ACC-07).
  def index
    unless can?(:office) || can?(:business_settings)
      landing = { field_work: admin_my_day_path, schedule: admin_schedule_path, manage_team: admin_team_path }.find { can?(_1.first) }&.last
      return redirect_to(landing) if landing

      return render "admin/shared/nothing_yet"
    end

    @business = current_business
    @checklist = SetupChecklist.new(@business, membership: Current.membership) # ACC-05
    Current.membership.offer_tour_if_due! unless impersonation # ACC-08: never on support's visit
    @dashboard = ActionDashboard.new(@business) # INS-01
    # #289: someone with visits of their own today, or still open from earlier, sees their own day
    # on Home (and reaches My day from it); otherwise the team's day, by person.
    if can?(:field_work)
      mine = Visit.open.joins(:assignments).where(visit_assignments: { user_id: current_user.id })
      @earlier_open = mine.where(scheduled_on: ...@business.today).count
      @own_day = @earlier_open.positive? || @dashboard.visits_today_for(current_user).any?
    end
  end
end
