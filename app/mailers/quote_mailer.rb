# QTE-04: the quote, emailed to the client with the owner's note, a summary, a button to the
# client page and the PDF attached.
class QuoteMailer < ClientMailer
  def sent
    @quote = Quote.find(params[:quote_id])
    subject = params[:subject].presence || self.class.default_subject(@quote)
    # Revised before it went out: never email unfinished edits (QTE-06).
    if @quote.draft? || (params[:revision] && params[:revision] != @quote.revision)
      return skip_changed_document(subject:, error: "The quote changed before the email went out. Send it again.")
    end

    @link = ClientLink.find(params[:link_id])
    @link = @quote.client_link! unless @link.usable? # revoked or expired while the email waited
    @note = params[:message].to_s
    pdf = @quote.current_pdf
    attachments[@quote.pdf_filename] = { mime_type: "application/pdf", content: pdf.is_a?(ActiveStorage::Blob) ? pdf.download : pdf }
    client_mail subject:, cc: params[:cc].presence
  end

  # QTE-05: confirms the client's approval, with what happens next and the approved PDF (which
  # shows who signed and when).
  def approved
    @quote = Quote.find(params[:quote_id])
    @approval = @quote.approval
    # The link they approved through, unless it stopped working since.
    @link = @approval.client_link&.usable? ? @approval.client_link : @quote.client_link!
    pdf = @quote.current_pdf
    attachments[@quote.pdf_filename] = { mime_type: "application/pdf", content: pdf.is_a?(ActiveStorage::Blob) ? pdf.download : pdf }
    values = MessageTemplate::Values.quote(@quote, link: @link).merge("signer_name" => @approval.signer_name)
    client_mail subject: custom_subject("quote_approved", values) || "You approved quote #{@quote.number} from #{@business.name}"
  end

  def self.default_subject(quote)
    "#{quote.approved? ? "Your approved quote" : "Quote"} #{quote.number} from #{quote.business.name}#{": #{quote.title}" if quote.title}"
  end
end
