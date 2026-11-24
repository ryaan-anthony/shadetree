# JOB-01: make the job for an approved quote (when the business doesn't do it automatically,
# or the automatic one didn't happen). A second press opens the same job.
#
# JOB-09 (split_jobs flag): Create job opens a picker of what's still to do, each line ticked at
# its remaining quantity, which can be lowered. Its token makes a resubmitted picker open the job
# it made; asking for more than is to do is refused, naming the jobs that hold it.
class Admin::QuoteJobsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office
  before_action :set_quote

  def new
    return redirect_to(admin_quote_path(@quote)) unless QuoteWork.split?(current_business) && @quote.approved?

    @lines = @quote.line_items.to_a
    @token = SecureRandom.base58(24)
  end

  def create
    split = QuoteWork.split?(current_business)
    job = Job.from_quote!(@quote, by: current_user, picks: (QuoteWork.picks_from(@quote, params[:picks]) if split), token: (params[:picker_token].to_s.first(64) if split))
    redirect_to admin_job_path(job), notice: (job.previously_new_record? ? "Job #{job.number} created from quote #{@quote.number}." : nil)
  rescue Job::NotOpen, QuoteWork::Refused, ActiveRecord::RecordInvalid => error
    reason = @quote.client.archived? ? "#{@quote.client.display_name} is archived. Restore them first." : error.message.delete_prefix("Validation failed: ")
    redirect_to (split && @quote.approved? ? new_admin_quote_job_path(@quote) : admin_quote_path(@quote)), alert: "Couldn't make a job from quote #{@quote.number}: #{reason}"
  end

  private

  def set_quote = @quote = Quote.find_by_param!(params[:quote_id])
end
