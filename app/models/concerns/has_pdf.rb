# A document with a downloadable PDF (QTE-02, ADR 0010); invoices reuse it (PAY-02). The model
# needs pdf_blob_id and pdf_digest columns and defines:
#   pdf_html     - the complete document (PdfDocument.render builds it from a template)
#   pdf_filename - e.g. "Quote Q-0042.pdf"
#   pdf_paper    - :letter or :a4
#   pdf_footer   - Chrome's footer template (page numbers), or nil
#   store_pdf?   - whether to keep the file (sent documents) or render fresh (drafts)
#
# The stored file is reused while the HTML is unchanged, so a sent revision downloads the
# same every time; any change (approval, say) makes a new one. Storing it touches neither
# the document's updated_at nor its lock_version.
module HasPdf
  extend ActiveSupport::Concern

  included do
    belongs_to :pdf_blob, class_name: "ActiveStorage::Blob", optional: true
  end

  # The PDF as it should be now: [data or blob, filename]. A blob when stored.
  def current_pdf
    html = pdf_html
    return PdfRenderer.render(html, paper: pdf_paper, footer: pdf_footer) unless store_pdf?

    digest = Digest::SHA256.hexdigest(html)
    return pdf_blob if pdf_blob && pdf_digest == digest

    data = PdfRenderer.render(html, paper: pdf_paper, footer: pdf_footer)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: pdf_filename, content_type: "application/pdf",
                                                  identify: false)
    previous = pdf_blob
    update_columns(pdf_blob_id: blob.id, pdf_digest: digest)
    previous&.purge_later
    self.pdf_blob = blob
  end
end
