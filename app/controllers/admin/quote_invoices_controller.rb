# PAY-01: invoice an approved quote as agreed (its lines, not the job's later changes).
class Admin::QuoteInvoicesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office

  def create
    quote = Quote.find_by_param!(params[:quote_id])
    invoice = Invoice.from_quote!(quote, by: current_user)
    redirect_to edit_admin_invoice_path(invoice), notice: "Invoice #{invoice.number} started from quote #{quote.number}."
  rescue Invoice::NotApproved, ActiveRecord::RecordInvalid => error
    redirect_to admin_quote_path(quote), alert: "Couldn't start an invoice: #{error.message.delete_prefix("Validation failed: ")}"
  end
end
