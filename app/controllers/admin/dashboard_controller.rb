class Admin::DashboardController < Admin::BaseController
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
    @dashboard = ActionDashboard.new(@business) # INS-01
  end
end
