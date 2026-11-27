# JOB-09: more of its quote's to-do work on an open job, from the same picker as Create job; and
# the office correcting anyone's logged work (each correction is another entry).
class Admin::JobWorkController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office
  before_action :set_job
  before_action :require_quote_work, only: %i[new create]

  def new
    @quote = @job.quote
    @lines = @quote.line_items.to_a
  end

  def create
    @job.add_from_quote!(QuoteWork.picks_from(@job.quote, params[:picks]))
    redirect_to admin_job_path(@job), notice: "Added to #{@job.number}."
  rescue Job::NotOpen, QuoteWork::Refused => error
    redirect_to new_admin_job_work_path(@job), alert: error.message
  end

  # The log's rows as the job page lists them: "<line id>-<user id>-<visit id or 0>" => total.
  def correct
    rows = params[:log].respond_to?(:key?) ? params[:log] : {}
    pairs = WorkEntry.where(job_id: @job.id).where.not(job_line_item_id: nil).distinct.pluck(:job_line_item_id, :user_id, :visit_id)
    changed = pairs.group_by { [ _2, _3 ] }.sum do |(user_id, visit_id), group|
      totals = group.filter_map { |line_id, *| (value = rows["#{line_id}-#{user_id}-#{visit_id || 0}"].to_s.strip).match?(/\A\d*\.?\d+\z/) && [ line_id, value ] }.to_h
      @job.log_work!(user: User.find(user_id), by: current_user, visit: visit_id && @job.visits.find(visit_id), totals:).size
    end
    redirect_to admin_job_path(@job, anchor: "work-log"), notice: (changed.positive? ? "Corrected the work log." : "Nothing changed.")
  rescue Job::NotOpen, QuoteWork::Refused => error
    redirect_to admin_job_path(@job, anchor: "work-log"), alert: error.message
  end

  private

  def set_job = @job = Job.find_by_param!(params[:job_id] || params[:id])

  def require_quote_work
    return if @job.quote && @job.open?

    redirect_to admin_job_path(@job), alert: ("#{@job.number} is #{@job.status_label.downcase}. Reopen it to add work." if @job.quote && !@job.open?)
  end
end
