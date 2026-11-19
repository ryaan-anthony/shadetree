# PAY-01: "Create invoice" on a job: a draft with the job's client, property, items, discount and
# taxes, opened in the builder. A job can be invoiced again (progress billing); each press makes
# a new draft, so the page says when one is already open.
class Admin::JobInvoicesController < Admin::BaseController
  requires_permission :office

  def create
    job = Job.find_by_param!(params[:job_id])
    invoice = Invoice.from_job!(job, by: current_user)
    redirect_to edit_admin_invoice_path(invoice), notice: "Invoice #{invoice.number} started from job #{job.number}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to admin_job_path(job), alert: "Couldn't start an invoice: #{error.record.errors.full_messages.to_sentence}"
  end
end
