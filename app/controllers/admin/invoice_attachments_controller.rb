# Removing a file from a draft invoice (PAY-01). A file a past revision was sent with stays
# stored for that record, as for quotes (QTE-06).
class Admin::InvoiceAttachmentsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office

  def destroy
    invoice = Invoice.find_by_param!(params[:invoice_id])
    return redirect_to(admin_invoice_path(invoice), alert: "Invoice #{invoice.number} can't be edited.") unless invoice.editable?

    attachment = invoice.attachments.find(params[:id])
    kept = invoice.revisions.any? { |revision| Array(revision.snapshot["files"]).any? { _1["blob_id"] == attachment.blob_id } }
    # A job's photo is shared with its visit: only this invoice's link to it goes. (If the visit
    # later deletes it, a revision's record of it points at nothing; the revision keeps the name.)
    shared = ActiveStorage::Attachment.where(blob_id: attachment.blob_id).where.not(id: attachment.id).exists?
    kept || shared ? attachment.delete : attachment.purge_later
    redirect_to edit_admin_invoice_path(invoice), notice: "#{attachment.filename} removed."
  end
end
