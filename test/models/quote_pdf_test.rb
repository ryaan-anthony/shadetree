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
    assert_nil doc.at_css(".pdf-online"), "a draft can't be answered yet"
  end

  test "a sent quote's PDF says how to answer it, and carries no link token" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    link = as_business(@business) { ClientLink.issue!(@quote) }
    doc = html
    assert_match "Awaiting approval", doc.at_css(".quote-doc-meta").text
    assert_match "open it from the email #{@business.name} sent you", doc.at_css(".pdf-online").text
    assert_no_match link.token, doc.to_html
    assert_nil doc.at_css("svg")
  end

  test "a sent PDF stays the same when the letterhead changes, another link is issued or the date passes" do
    as_business(@business) { @quote.update_columns(status: "sent", expires_on: @business.today + 1) }
    with_fake_pdf_renderer do |calls|
      first = as_business(@business) { @quote.reload.current_pdf }
      @business.update!(phone: "555-999-0000")
      as_business(@business) { ClientLink.issue!(@quote) }
      travel 3.days do
        assert_equal first, as_business(@business) { Quote.find(@quote.id).current_pdf }
      end
      assert_equal 1, calls.size
      assert_match "Awaiting approval", calls.last[:html][/Status.{0,80}/m], "the status comes from the status, not the date"

      as_business(@business) { Quote.find(@quote.id).tap { _1.update!(title: "Fall cleanup") }.current_pdf }
      assert_equal 2, calls.size, "an edit to the quote makes a new file"

      as_business(@business) { @quote.client.update!(display_name: "Maria Lopez-Reyes") }
      as_business(@business) { Quote.find(@quote.id).current_pdf }
      assert_equal 3, calls.size, "so does a change to the client it names"
      assert_match "Maria Lopez-Reyes", calls.last[:html]

      version = Quote::PDF_VERSION
      Quote.send(:remove_const, :PDF_VERSION)
      Quote.const_set(:PDF_VERSION, version + 1)
      as_business(@business) { Quote.find(@quote.id).current_pdf }
      assert_equal 4, calls.size, "and bumping PDF_VERSION replaces stored files"
    ensure
      if version
        Quote.send(:remove_const, :PDF_VERSION)
        Quote.const_set(:PDF_VERSION, version)
      end
    end
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

  test "losing the race to an older state re-renders: an approval doesn't come back as 'Awaiting approval'" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    with_fake_pdf_renderer do |calls|
      sent = as_business(@business) { Quote.find(@quote.id) }
      as_business(@business) { @quote.update_column(:status, "approved") }
      approved = as_business(@business) { Quote.find(@quote.id) }
      as_business(@business) { sent.current_pdf } # the older state is stored first
      as_business(@business) { approved.current_pdf }
      assert_match "Approved", calls.last[:html][/Status.{0,80}/m]
      assert_equal 3, calls.size, "the approved render lost the race, then rendered again"
      assert_equal Digest::SHA256.hexdigest(approved.pdf_fingerprint), as_business(@business) { @quote.reload.pdf_digest }
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
