# Removing a file from a draft quote (QTE-01).
class Admin::QuoteAttachmentsController < Admin::BaseController
  requires_permission :office

  def destroy
    quote = Quote.find_by_param!(params[:quote_id])
    return redirect_to(admin_quotes_path, alert: "Quote #{quote.number} can't be edited.") unless quote.editable?

    attachment = quote.attachments.find(params[:id])
    attachment.purge_later
    redirect_to edit_admin_quote_path(quote), notice: "#{attachment.filename} removed."
  end
end
