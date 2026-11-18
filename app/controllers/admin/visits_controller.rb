# JOB-02: scheduling a job's visits (Owners and Admins, the `schedule` permission): book one,
# move it, change who's going, cancel or restore it, or mark it done. Every change is recorded
# with who made it.
class Admin::VisitsController < Admin::BaseController
  requires_permission :schedule
  before_action :set_job
  before_action :set_visit, only: %i[edit update cancel restore complete]
  before_action :require_open_job, only: %i[new create]

  def new
    on = Visit.parse_date(params[:on]) # from the calendar's "Needs scheduling" (JOB-03); never a past day
    @visit = @job.visits.new(scheduled_on: [ on, current_business.today ].compact.max, timing: "window", start_time: "08:00", window_end_time: "10:00",
                             duration_minutes: @job.suggested_visit_minutes)
  end

  # One visit, or one per day for work over several days. Warnings (hours, closures, someone
  # already booked) come back to the form first; "Schedule anyway" books it regardless.
  def create
    attrs = visit_params.merge(created_by: current_user)
    @visit = @job.visits.new(attrs)
    @hours = OpeningHours.new(current_business)
    dates = Visit.plan_dates(attrs[:scheduled_on], through: params[:through], extra: params[:extra_dates],
                             skip_closed: params[:skip_closed] == "1", hours: @hours)
    if dates.size > Visit::MAX_DAYS
      @visit.errors.add(:base, "That's more than #{Visit::MAX_DAYS} days. Book them in parts.")
      return render :new, status: :unprocessable_content
    end
    visits = dates.empty? ? [ @visit ] : dates.each_with_index.map { |date, index| index.zero? ? @visit.tap { _1.scheduled_on = date } : @job.visits.new(attrs.merge(scheduled_on: date)) }
    unless visits.map(&:valid?).all?
      (visits - [ @visit ]).select { _1.errors.any? }.each { |other| other.errors.each { @visit.errors.add(:base, "#{other.scheduled_on.strftime("%a, %b %-d")}: #{_1.full_message}") } }
      return render :new, status: :unprocessable_content
    end
    return render(:new, status: :unprocessable_content) if warn?(visits) # Turbo only shows a form's non-redirect response with an error status

    Visit.schedule_all!(visits, by: current_user, notify_client: notify_client?)
    notice = visits.one? ? "Visit scheduled for #{@visit.when_label}." : "#{visits.size} visits scheduled, #{visits.first.scheduled_on.strftime("%b %-d")} to #{visits.last.scheduled_on.strftime("%b %-d")}."
    redirect_to admin_job_path(@job), notice:
  rescue Visit::BadDates => error
    @visit.errors.add(:base, error.message)
    render :new, status: :unprocessable_content
  rescue ActiveRecord::RecordInvalid => error
    @visit.errors.add(:base, error.message.delete_prefix("Validation failed: ")) unless error.record == @visit
    render :new, status: :unprocessable_content
  rescue Visit::NotOpen => error # the job was finished meanwhile
    redirect_to admin_job_path(@job), alert: error.message
  end

  def edit; end

  def update
    @visit.assign_attributes(visit_params)
    return render(:edit, status: :unprocessable_content) unless @visit.valid?
    return render(:edit, status: :unprocessable_content) if @visit.when_or_crew_changed? && warn?([ @visit ])

    @visit.reload.reschedule!(visit_params, by: current_user, notify_client: notify_client?)
    redirect_to admin_job_path(@job), notice: "Visit saved: #{@visit.when_label}."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_admin_job_visit_path(@job, @visit), alert: "This visit was changed in another tab or by someone else. Here's the latest version."
  rescue Visit::NotOpen => error
    redirect_to admin_job_path(@job), alert: error.message
  end

  def cancel = transition { @visit.cancel!(by: current_user, reason: params[:reason], notify_client: notify_client?) && "Visit on #{@visit.when_label} cancelled." }
  def restore = transition { @visit.restore!(by: current_user, notify_client: notify_client?) && "Visit on #{@visit.when_label} restored." }
  def complete = transition { @visit.complete!(by: current_user) && "Visit on #{@visit.when_label} marked done." }

  private

  def set_job = @job = Job.includes(:client, :property).find_by_param!(params[:job_id])

  # Shows the warnings unless these exact warnings were seen and confirmed ("Schedule anyway"):
  # the form carries a digest of what it showed, so a change after that is checked again.
  def warn?(visits)
    @warnings = VisitWarnings.for(visits, hours: @hours)
    @warnings.any? && params[:confirm] != self.class.digest(@warnings)
  end

  def self.digest(warnings) = Digest::SHA256.hexdigest(warnings.join("\n"))
  helper_method def confirm_digest = self.class.digest(@warnings)

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

  # JOB-05: "Email the client about this" unticked means they aren't told about this change.
  def notify_client? = params[:notify_client] != "0"

  def visit_params
    params.require(:visit).permit(:scheduled_on, :timing, :start_time, :window_end_time, :duration_hours, :instructions, :client_note, :lock_version, assignee_ids: [])
  end
end
