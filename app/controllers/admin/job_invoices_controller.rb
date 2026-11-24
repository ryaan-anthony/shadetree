# PAY-01: "Create invoice" on a job: a draft with the job's client, property, items, discount and
# taxes, opened in the builder. PAY-06: with split jobs, once completed, its unbilled lines as done
# (WorkBilling); with nothing to bill it's refused, saying why.
class Admin::JobInvoicesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office

  def create
    job = Job.find_by_param!(params[:job_id])
    invoice = Invoice.from_job!(job, by: current_user)
    redirect_to edit_admin_invoice_path(invoice), notice: "Invoice #{invoice.number} started from job #{job.number}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to admin_job_path(job), alert: "Couldn't start an invoice: #{error.record.errors.full_messages.to_sentence}"
  rescue Invoice::Unpriced, WorkBilling::Refused => error # JOB-09, PAY-06
    redirect_to admin_job_path(job), alert: "Couldn't start an invoice: #{error.message}"
  end
end
