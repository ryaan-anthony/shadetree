# Removing a file from a draft quote (QTE-01).
class Admin::QuoteAttachmentsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office
  include OwnQuoteAccess
  allow_any_member only: :destroy # QTE-07: also on their own drafts

  def destroy
    scope = reachable_quotes or return
    quote = scope.find_by_param!(params[:quote_id])
    return redirect_to(admin_quotes_path, alert: "Quote #{quote.number} can't be edited.") unless quote.editable?

    attachment = quote.attachments.find(params[:id])
    # A file a past revision was sent with stays stored for that record (QTE-06).
    kept = quote.revisions.any? { |revision| Array(revision.snapshot["files"]).any? { _1["blob_id"] == attachment.blob_id } }
    kept ? attachment.delete : attachment.purge_later
    redirect_to edit_admin_quote_path(quote), notice: "#{attachment.filename} removed."
  end
end
