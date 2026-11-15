require "test_helper"

# QTE-02: what goes into a quote's PDF, and when the stored one is reused (HasPdf).
class QuotePdfTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com", phone: "555-380-0000", address_line1: "1 Depot Rd", city: "Austin")
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client: maria)
      quote.assign_attributes(title: "Spring cleanup", internal_notes: "Gate code 1234")
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180", "taxable" => "0" } ])
      quote.save!
      quote
    end
  end

  def html = Nokogiri::HTML(as_business(@business) { @quote.reload.pdf_html })

  test "the HTML is the client page's document under the business's letterhead, and self-contained" do
    doc = html
    assert_match @business.name, doc.at_css(".pdf-letterhead").text
    assert_match "1 Depot Rd", doc.at_css(".pdf-contact").text
    assert_equal "Spring cleanup", doc.at_css(".quote-doc-title").text
    assert_match "Draft", doc.at_css(".quote-doc-meta").text
    assert_no_match "Gate code", doc.text
    assert_match "Public Sans", doc.at_css("style").text
    # Nothing to fetch: no external stylesheets, scripts or images.
    assert_empty doc.css("link[rel=stylesheet], script")
    doc.css("img").each { assert_match(/\Adata:/, _1["src"]) }
    assert_nil doc.at_css(".pdf-qr"), "a draft has no online version"
  end

  test "a sent quote with a link carries a QR code for its client page" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    link = as_business(@business) { ClientLink.issue!(@quote) }
    assert as_business(@business) { @quote.reload.pdf_online_url }.end_with?("/c/#{link.token}")
    assert html.at_css("svg.pdf-qr")
    assert_match "Awaiting approval", html.at_css(".quote-doc-meta").text
  end

  test "drafts are rendered fresh each time and never stored" do
    with_fake_pdf_renderer do |calls|
      2.times { assert as_business(@business) { @quote.current_pdf }.start_with?("%PDF") }
      assert_equal 2, calls.size
      assert_nil as_business(@business) { @quote.reload.pdf_blob }
    end
  end

  test "a sent quote's PDF is stored and reused until something on it changes" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    with_fake_pdf_renderer do |calls|
      lock_version = as_business(@business) { @quote.reload.lock_version }
      first = as_business(@business) { @quote.current_pdf }
      again = as_business(@business) { Quote.find(@quote.id).current_pdf }
      assert_equal first, again
      assert_equal 1, calls.size
      assert_equal "Quote #{@quote.number}.pdf", first.filename.to_s
      assert_equal lock_version, as_business(@business) { @quote.reload.lock_version }, "storing doesn't touch the quote"

      as_business(@business) { @quote.update_column(:status, "approved") }
      assert_enqueued_with(job: ActiveStorage::PurgeJob) do
        changed = as_business(@business) { Quote.find(@quote.id).current_pdf }
        assert_not_equal first, changed
      end
      assert_equal 2, calls.size
    end
  end

  test "two first downloads at once keep one file and delete the other" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    with_fake_pdf_renderer do
      one, two = as_business(@business) { [ Quote.find(@quote.id), Quote.find(@quote.id) ] }
      first = as_business(@business) { one.current_pdf }
      assert_enqueued_with(job: ActiveStorage::PurgeJob) do
        assert_equal first, as_business(@business) { two.current_pdf }, "the second keeps the stored file"
      end
      assert_equal first.id, as_business(@business) { @quote.reload.pdf_blob_id }
    end
  end

  test "a stylesheet change alone doesn't make a new file" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    with_fake_pdf_renderer do |calls|
      as_business(@business) { @quote.current_pdf }
      css = PdfDocument.method(:stylesheet)
      PdfDocument.define_singleton_method(:stylesheet) { css.call + ".new-rule{color:red}" }
      as_business(@business) { Quote.find(@quote.id).current_pdf }
      assert_equal 1, calls.size
    ensure
      PdfDocument.define_singleton_method(:stylesheet, css)
    end
  end

  test "sending or answering a quote makes its PDF in the background" do
    assert_enqueued_with(job: QuotePdfJob, args: [ @business.id, @quote.id ]) { as_business(@business) { @quote.update!(status: "sent") } }
    assert_no_enqueued_jobs(only: QuotePdfJob) { as_business(@business) { @quote.update!(title: "Renamed") } }
  end

  test "the background job makes the PDF ahead of the first download" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    with_fake_pdf_renderer do |calls|
      QuotePdfJob.perform_now(@business.id, @quote.id)
      assert_equal 1, calls.size
      assert as_business(@business) { @quote.reload.pdf_blob }
    end
  end
end
