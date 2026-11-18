# JOB-02: scheduling a job's visits (Owners and Admins, the `schedule` permission): book one,
# move it, change who's going, cancel or restore it, or mark it done. Every change is recorded
# with who made it.
class Admin::VisitsController < Admin::BaseController
  requires_permission :schedule
  before_action :set_job
  before_action :set_visit, only: %i[edit update cancel restore complete]
  before_action :require_open_job, only: %i[new create]

  def new
    @visit = @job.visits.new(scheduled_on: current_business.today, timing: "window", start_time: "08:00", window_end_time: "10:00",
                             duration_minutes: @job.suggested_visit_minutes)
  end

  # One visit, or one per day for work over several days. Warnings (hours, closures, someone
  # already booked) come back to the form first; "Schedule anyway" books it regardless.
  def create
    attrs = visit_params.merge(created_by: current_user)
    @visit = @job.visits.new(attrs)
    dates = Visit.plan_dates(attrs[:scheduled_on], through: params[:through], extra: params[:extra_dates],
                             skip_closed: params[:skip_closed] == "1", hours: OpeningHours.new(current_business))
    if dates.size > Visit::MAX_DAYS
      @visit.errors.add(:base, "That's more than #{Visit::MAX_DAYS} days. Book them in parts.")
      return render :new, status: :unprocessable_content
    end
    visits = dates.empty? ? [ @visit ] : dates.each_with_index.map { |date, index| index.zero? ? @visit.tap { _1.scheduled_on = date } : @job.visits.new(attrs.merge(scheduled_on: date)) }
    return render(:new, status: :unprocessable_content) unless visits.map(&:valid?).all?
    return render(:new, status: :unprocessable_content) if warn?(visits) # Turbo only shows a form's non-redirect response with an error status

    Visit.schedule_all!(visits, by: current_user)
    notice = visits.one? ? "Visit scheduled for #{@visit.when_label}." : "#{visits.size} visits scheduled, #{visits.first.scheduled_on.strftime("%b %-d")} to #{visits.last.scheduled_on.strftime("%b %-d")}."
    redirect_to admin_job_path(@job), notice:
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  rescue Visit::NotOpen => error # the job was finished meanwhile
    redirect_to admin_job_path(@job), alert: error.message
  end

  def edit; end

  def update
    @visit.assign_attributes(visit_params)
    return render(:edit, status: :unprocessable_content) unless @visit.valid?
    return render(:edit, status: :unprocessable_content) if @visit.when_or_crew_changed? && warn?([ @visit ])

    @visit.reload.reschedule!(visit_params, by: current_user)
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

  # Shows the warnings unless they were seen and the change confirmed ("Schedule anyway").
  def warn?(visits)
    @warnings = VisitWarnings.for(visits)
    @warnings.any? && params[:confirm].blank?
  end

  def require_open_job
    redirect_to admin_job_path(@job), alert: "#{@job.number} is #{@job.status_label.downcase}. Reopen it to schedule visits." unless @job.open?
  end
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
