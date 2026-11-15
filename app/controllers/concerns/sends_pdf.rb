# Sends a document's PDF (HasPdf, QTE-02) as a download. Rendering can fail (Chrome missing
# or out of time): that's reported and the person is sent back with a message, not a 500.
module SendsPdf
  extend ActiveSupport::Concern

  private

  def send_pdf(document, back:)
    pdf = document.current_pdf
    data = pdf.is_a?(ActiveStorage::Blob) ? pdf.download : pdf
    send_data data, filename: document.pdf_filename, type: "application/pdf", disposition: "attachment"
  rescue PdfRenderer::Error => error
    Rails.error.report(error, context: { document: document.to_gid.to_s })
    redirect_to back, alert: "The PDF couldn't be made just now. Please try again in a minute."
  end
end
