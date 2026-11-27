# PAY-01: invoice an approved quote. PAY-06 (WorkBilling): its completed jobs' unbilled lines, or
# with no jobs its own lines directly; with nothing to bill it's refused, saying why. PAY-08:
# progress=1 bills part of what isn't done yet.
class Admin::QuoteInvoicesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office

  def create
    quote = Quote.find_by_param!(params[:quote_id])
    invoice = progress? ? WorkBilling.bill_progress!(quote, by: current_user, discount: params[:discount]) : Invoice.from_quote!(quote, by: current_user, discount: params[:discount])
    redirect_to edit_admin_invoice_path(invoice), notice: "#{progress? ? "Progress invoice" : "Invoice"} #{invoice.number} started from quote #{quote.number}."
  rescue Invoice::NotApproved, Invoice::Unpriced, WorkBilling::Refused, ActiveRecord::RecordInvalid => error
    redirect_to admin_quote_path(quote), alert: "Couldn't start an invoice: #{error.message.delete_prefix("Validation failed: ")}"
  end

  private

  def progress? = params[:progress].present?
end
