# JOB-09: more of its quote's to-do work on an open job, from the same picker as Create job.
class Admin::JobWorkController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office
  before_action :set_job

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

  private

  def set_job
    @job = Job.find_by_param!(params[:job_id])
    usable = QuoteWork.split?(current_business) && @job.quote && @job.open?
    redirect_to admin_job_path(@job), alert: ("#{@job.number} is #{@job.status_label.downcase}. Reopen it to add work." if @job.quote && !@job.open?) unless usable
  end
end
