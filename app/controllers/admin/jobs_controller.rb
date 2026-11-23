# Jobs (JOB-01): the list, a job's page, a job from scratch, and finishing or cancelling one.
# Technicians don't get here: they see jobs through their assigned visits (JOB-04).
class Admin::JobsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed, reads: %i[search]
  requires_permission :office
  before_action :set_job, only: %i[show edit update complete cancel reopen]
  before_action :require_open, only: %i[edit update]

  PER_PAGE = 25

  filters_by_location Job, only: %i[index search] # CAT-07

  def index = load_list

  def search
    load_list
    render partial: "results", layout: false
  end

  def show; end

  # From scratch, for work agreed by phone (?client=<uid> preselects the client).
  def new
    client = Client.active.find_by(uid: params[:client])
    @job = Job.new(client:, property: client&.properties&.find_by(billing: true) || client&.properties&.first, location: current_membership.document_location)
  end

  def create
    @job = Job.new(job_params.merge(created_by: current_user))
    @job.location = picked_location(params.dig(:job, :location))
    @job.client = Client.active.find_by(uid: params.dig(:job, :client).to_s)
    @job.property = @job.client&.properties&.find_by(uid: params.dig(:job, :property).to_s)
    if @job.client.nil?
      @job.errors.add(:client, "Choose a client, or add a new one.")
      render :new, status: :unprocessable_content
    elsif @job.save
      redirect_to admin_job_path(@job), notice: "Job #{@job.number} created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    stale = params.dig(:job, :lock_version).present? && params.dig(:job, :lock_version).to_i != @job.lock_version
    @job.assign_attributes(job_params)
    @job.property = @job.client.properties.find_by(uid: params.dig(:job, :property).to_s) if params[:job]&.key?(:property)
    @job.location = picked_location(params.dig(:job, :location)) || @job.location if params[:job]&.key?(:location)
    if @job.save
      redirect_to admin_job_path(@job), notice: "Job #{@job.number} saved."
    else
      render :edit, status: :unprocessable_content
    end
  rescue QuoteWork::Refused => error # JOB-09: more than the quote has to do
    @job.errors.add(:base, error.message)
    render :edit, status: :unprocessable_content
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_admin_job_path(@job), alert: "#{@job.number} was changed in another tab or by someone else. Here's the latest version."
  rescue ActiveRecord::RecordNotFound
    raise unless stale # a line removed in the other tab

    redirect_to edit_admin_job_path(@job), alert: "#{@job.number} was changed in another tab or by someone else. Here's the latest version."
  end

  def complete
    @job.complete!(by: current_user, done: done_param)
    redirect_to admin_job_path(@job), notice: "Job #{@job.number} completed."
  rescue Job::NotOpen, QuoteWork::Refused => error
    redirect_to admin_job_path(@job), alert: error.message
  end

  def cancel
    @job.cancel!(by: current_user, reason: params[:reason], notify_client: params[:notify_client] != "0")
    redirect_to admin_job_path(@job), notice: "Job #{@job.number} cancelled."
  rescue Job::NotOpen, ActiveRecord::RecordInvalid => error
    redirect_to admin_job_path(@job), alert: error.message.delete_prefix("Validation failed: ")
  end

  def reopen
    @job.reopen!
    redirect_to admin_job_path(@job), notice: "Job #{@job.number} reopened."
  rescue Job::NotOpen, QuoteWork::Refused => error
    redirect_to admin_job_path(@job), alert: error.message
  end

  private

  # JOB-09: what was done on each line, from the Complete dialog ({ job line id => quantity }).
  def done_param
    rows = params[:done]
    return unless rows.respond_to?(:key?) && QuoteWork.split?(current_business)

    @job.line_items.each_with_object({}) { |line, done| (value = rows[line.id.to_s].to_s.strip).match?(/\A-?\d*\.?\d+\z/) && done[line.id] = value }
  end

  def set_job = @job = Job.includes(:client, :property, :quote, line_items: :catalog_item).find_by_param!(params[:id])

  # A finished job is read-only until it's reopened.
  def require_open
    redirect_to admin_job_path(@job), alert: "#{@job.number} is #{@job.status_label.downcase}. Reopen it to make changes." unless @job.open?
  end

  # lock_version: a save from a tab opened before someone else's change is refused, not merged.
  def job_params = params.fetch(:job, {}).permit(:title, :instructions, :internal_notes, :lock_version,
                                                  line_items_attributes: %i[id _destroy catalog_item_uid name description quantity unit unit_price taxable])

  def load_list
    @filter = params[:filter].presence_in(Job::FILTERS.keys) || "open"
    @query = params[:q].to_s.strip.first(100)
    scope = Job.filtered(@filter).search(@query)
    @total_count = scope.count
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @jobs = scope.includes(:client, :property, :quote, :location).order(created_at: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @counts = Job.filter_counts unless request.post? # the tabs are outside the results frame
    @any_jobs = @total_count.positive? || Job.exists?
  end
end
