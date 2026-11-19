# JOB-04: one of the signed-in member's visits, from their day view: where and when, how to get
# in and reach the client, what to do, and Start / Complete. Any other visit is "not found".
class Admin::MyVisitsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :field_work
  before_action :set_visit

  def show
    @note = VisitNote.new # not through @visit.notes, which would list it
  end

  def start = transition("Started. Complete it when you're done.") { @visit.start!(by: current_user) }
  def complete = transition("Completed. Nice work.") { @visit.complete!(by: current_user) }
  def reopen = transition("Reopened.") { @visit.reopen!(by: current_user) }

  private

  def set_visit
    @visit = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id })
                  .includes(:business, :assignees, :notes, job: [ :client, :property, { line_items: :catalog_item } ]).find_by_param!(params[:id])
    @job = @visit.job
  end

  def transition(notice)
    yield
    redirect_to admin_my_visit_path(@visit), notice:
  rescue Visit::NotOpen => error
    redirect_to admin_my_visit_path(@visit), alert: error.message
  end
end
