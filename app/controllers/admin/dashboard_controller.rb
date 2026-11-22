class Admin::DashboardController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  allow_any_member
  # CAT-07; JOB-06: your follow-ups on Home follow the filter too (owner, 2026-11-22)
  filters_by_location ServiceRequest, Quote, Job, Invoice, Visit, RequestFollowUp, Payment, QuoteResponse, only: :index

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
    @dashboard = ActionDashboard.new(@business) # INS-01
    # #289: someone with visits or request follow-ups of their own today, or still open from
    # earlier, sees their own day on Home (and reaches My day from it); otherwise the team's day,
    # by person. JOB-06 (owner, 2026-11-22): follow-ups count, listed and placed as My day does.
    @my_day = MyDay.new(@business, current_user, upcoming_days: 0) if can?(:field_work)
  end
end
