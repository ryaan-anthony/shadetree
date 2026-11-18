# JOB-02: scheduling a job's visits (Owners and Admins, the `schedule` permission): book one,
# move it, change who's going, cancel or restore it, or mark it done. Every change is recorded
# with who made it.
class Admin::VisitsController < Admin::BaseController
  requires_permission :schedule
  before_action :set_job
  before_action :set_visit, only: %i[edit update cancel restore complete]

  def new
    @visit = @job.visits.new(scheduled_on: current_business.today, timing: "window", start_time: "08:00", window_end_time: "10:00",
                             duration_minutes: @job.suggested_visit_minutes)
  end

  def create
    return redirect_to(admin_job_path(@job), alert: "#{@job.number} is #{@job.status_label.downcase}. Reopen it to schedule visits.") unless @job.open?

    @visit = @job.visits.new(visit_params.merge(created_by: current_user))
    @visit.schedule!(by: current_user)
    redirect_to admin_job_path(@job), notice: "Visit scheduled for #{@visit.when_label}."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit; end

  def update
    @visit.reschedule!(visit_params, by: current_user)
    redirect_to admin_job_path(@job), notice: "Visit saved: #{@visit.when_label}."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_admin_job_visit_path(@job, @visit), alert: "This visit was changed in another tab or by someone else. Here's the latest version."
  rescue Visit::NotOpen => error
    redirect_to admin_job_path(@job), alert: error.message
  end

  def cancel = transition { @visit.cancel!(by: current_user, reason: params[:reason]) && "Visit on #{@visit.when_label} cancelled." }
  def restore = transition { @visit.restore!(by: current_user) && "Visit on #{@visit.when_label} restored." }
  def complete = transition { @visit.complete!(by: current_user) && "Visit on #{@visit.when_label} marked done." }

  private

  def set_job = @job = Job.includes(:client, :property).find_by_param!(params[:job_id])
  def set_visit
    @visit = @job.visits.includes(:assignees).find_by_param!(params[:id])
    @visit_label = @visit.when_label # before any change, for the page title
  end

  def transition
    redirect_to admin_job_path(@job, anchor: "visits"), notice: yield
  rescue Visit::NotOpen, ActiveRecord::RecordInvalid => error
    redirect_to admin_job_path(@job, anchor: "visits"), alert: error.message.delete_prefix("Validation failed: ")
  end

  def visit_params
    params.require(:visit).permit(:scheduled_on, :timing, :start_time, :window_end_time, :duration_hours, :instructions, :lock_version, assignee_ids: [])
  end
end
