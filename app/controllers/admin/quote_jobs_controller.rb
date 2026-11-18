# JOB-01: make the job for an approved quote (when the business doesn't do it automatically,
# or the automatic one didn't happen). A second press opens the same job.
class Admin::QuoteJobsController < Admin::BaseController
  requires_permission :office

  def create
    quote = Quote.find_by_param!(params[:quote_id])
    existing = quote.job
    job = Job.from_quote!(quote, by: current_user)
    redirect_to admin_job_path(job), notice: (existing ? nil : "Job #{job.number} created from quote #{quote.number}.")
  rescue Job::NotOpen, ActiveRecord::RecordInvalid => error
    redirect_to admin_quote_path(quote), alert: "Couldn't make a job from quote #{quote.number}: #{error.message.delete_prefix("Validation failed: ")}"
  end
end
