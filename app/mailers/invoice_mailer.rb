# PAY-02: the invoice, emailed to the client with the sender's note, what's owed and when, a
# button to the invoice page and the PDF attached.
class InvoiceMailer < ClientMailer
  def sent
    @invoice = Invoice.find(params[:invoice_id])
    subject = params[:subject].presence || self.class.default_subject(@invoice)
    # Revised or voided before it went out: never email unfinished edits or a void invoice.
    if @invoice.draft? || @invoice.void? || (params[:revision] && params[:revision] != @invoice.revision)
      return skip_changed_document(subject:, error: "The invoice changed before the email went out. Send it again.")
    end

    @link = ClientLink.find(params[:link_id])
    @link = @invoice.client_link! unless @link.usable? # revoked while the email waited
    @note = params[:message].to_s
    pdf = @invoice.current_pdf
    attachments[@invoice.pdf_filename] = { mime_type: "application/pdf", content: pdf.is_a?(ActiveStorage::Blob) ? pdf.download : pdf }
    client_mail subject:, cc: params[:cc].presence
  end

  def self.default_subject(invoice) = "Invoice #{invoice.number} from #{invoice.business.name}#{": #{invoice.title}" if invoice.title}"
end
