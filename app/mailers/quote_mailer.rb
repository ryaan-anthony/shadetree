# QTE-04: the quote, emailed to the client with the owner's note, a summary, a button to the
# client page and the PDF attached.
class QuoteMailer < ClientMailer
  def sent
    @quote = Quote.find(params[:quote_id])
    @link = ClientLink.find(params[:link_id])
    @link = @quote.client_link! unless @link.usable? # revoked or expired while the email waited
    @note = params[:message].to_s
    pdf = @quote.current_pdf
    attachments[@quote.pdf_filename] = { mime_type: "application/pdf", content: pdf.is_a?(ActiveStorage::Blob) ? pdf.download : pdf }
    client_mail subject: params[:subject].presence || self.class.default_subject(@quote), cc: params[:cc].presence
  end

  def self.default_subject(quote) = "Quote #{quote.number} from #{quote.business.name}#{": #{quote.title}" if quote.title}"
end
