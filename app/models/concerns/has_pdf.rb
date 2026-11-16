# A document with a downloadable PDF (QTE-02, ADR 0010); invoices reuse it (PAY-02). The model
# needs pdf_blob_id and pdf_digest columns and defines:
#   pdf_html     - the complete document (PdfDocument.render builds it from a template)
#   pdf_filename - e.g. "Quote Q-0042.pdf"
#   pdf_paper    - :letter or :a4
#   pdf_footer   - Chrome's footer template (page numbers), or nil
#   store_pdf?   - whether to keep the file (sent documents) or render fresh (drafts)
#
# The stored file is reused while the document's content is unchanged (the inlined stylesheet
# isn't part of the key, so a deploy doesn't re-render every sent document), and a sent
# revision downloads the same every time; a change on it (approval, say) makes a new one.
# Storing touches neither the document's updated_at nor its lock_version, and two first
# downloads at once keep one file and delete the other.
module HasPdf
  extend ActiveSupport::Concern

  included do
    belongs_to :pdf_blob, class_name: "ActiveStorage::Blob", optional: true
  end

  # The PDF as it should be now: binary data for a draft, a blob when stored.
  def current_pdf(attempts: 3)
    html = pdf_html
    return PdfRenderer.render(html, paper: pdf_paper, footer: pdf_footer) unless store_pdf?

    digest = Digest::SHA256.hexdigest(html.sub(%r{<style>.*?</style>}m, ""))
    return pdf_blob if pdf_blob && pdf_digest == digest

    data = PdfRenderer.render(html, paper: pdf_paper, footer: pdf_footer)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: pdf_filename, content_type: "application/pdf",
                                                  identify: false)
    previous_id = pdf_blob_id
    # Compare-and-set: if another request stored one meanwhile, keep theirs and drop ours.
    stored = self.class.where(id:, pdf_blob_id: previous_id).update_all([ "pdf_blob_id = ?, pdf_digest = ?", blob.id, digest ]) == 1
    unless stored
      # Another request stored one meanwhile, possibly of an older state (sent, while this one
      # rendered approved). Drop ours and check again against what's stored now.
      blob.purge_later
      reload
      return attempts > 1 ? current_pdf(attempts: attempts - 1) : pdf_blob
    end

    ActiveStorage::Blob.find_by(id: previous_id)&.purge_later
    self.pdf_digest = digest
    self.pdf_blob = blob
  end
end
