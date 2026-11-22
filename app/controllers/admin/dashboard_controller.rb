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
    @tour_offer = tour_offer
    @dashboard = ActionDashboard.new(@business) # INS-01
    # #289: someone with visits or request follow-ups of their own today, or still open from
    # earlier, sees their own day on Home (and reaches My day from it); otherwise the team's day,
    # by person. JOB-06 (owner, 2026-11-22): follow-ups count, listed and placed as My day does.
    # Anyone who can be given follow-ups (an office-only role too, without My day).
    @my_day = MyDay.new(@business, current_user, upcoming_days: 0) if can?(:field_work) || RequestFollowUp.assignable?(Current.membership)
  end

  private

  # ACC-08: the tour offer on Home: one already made (to a creator, or below), or, for an existing
  # business's Owner whose checklist isn't complete, made now (owner, 2026-11-22). Never made on
  # support's visit; Turbo's hover prefetch shows it without recording it.
  def tour_offer
    membership = Current.membership
    return false unless membership
    return true if membership.tour_offered?
    return false if impersonation || !membership.tour_offer_due? || @checklist.complete?

    request.headers["X-Sec-Purpose"] == "prefetch" || membership.offer_tour!
  end
end
