# JOB-03: the team calendar (Owners and Admins; technicians use My day). A week or a day of
# visits on a time grid, or an agenda list on phones, filtered by member; the jobs still
# needing a visit beside it. Opening a visit shows it in a side panel.
class Admin::ScheduleController < Admin::BaseController
  requires_permission :schedule

  def show
    date = Date.iso8601(params[:date].to_s) rescue nil
    member = params[:member].presence
    member = nil unless member == "unassigned" || current_business.business_users.exists?(user_id: member.to_i)
    @schedule = ScheduleView.new(current_business, view: params[:view], date:, member: member && (member == "unassigned" ? member : member.to_i),
                                                   color_by: params[:color])
  end

  # The details of one visit, for the panel beside the calendar.
  def visit
    @visit = Visit.includes(:assignees, job: %i[client property]).find_by_param!(params[:id])
    render partial: "admin/schedule/visit", locals: { visit: @visit }, layout: false if turbo_frame_request?
  end
end
