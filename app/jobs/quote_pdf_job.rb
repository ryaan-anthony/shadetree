# Makes and stores a quote's PDF ahead of the first download (QTE-02, ADR 0010): enqueued
# whenever a quote's status changes to one the client sees (sent, approved, …). A download
# before it has run renders inline instead.
class QuotePdfJob < ApplicationJob
  retry_on PdfRenderer::Error, wait: :polynomially_longer, attempts: 3

  def perform(business_id, quote_id)
    business = Business.find_by(id: business_id) or return
    Tenancy.with_business(business) { Quote.find_by(id: quote_id)&.current_pdf }
  end
end
