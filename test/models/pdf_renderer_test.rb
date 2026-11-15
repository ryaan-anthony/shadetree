require "test_helper"

# QTE-02 (ADR 0010): real PDFs from headless Chrome. Skipped where Chrome isn't installed.
class PdfRendererTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com", phone: "555-380-0000")
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                             properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", billing: true } ])
      quote = Quote.start(client: maria)
      quote.assign_attributes(title: "Spring cleanup", internal_notes: "Gate code 1234", terms: "Net 15.")
      quote.sync_line_items((1..45).map { |i| { "key" => "k#{i}", "name" => "Item #{i}", "description" => "Details for item #{i}", "quantity" => "1", "unit_price" => "10", "taxable" => "0" } })
      quote.save!
      quote
    end
  end

  # Only a missing Chrome skips; a render that fails is a failure.
  setup do
    chrome = ENV["BROWSER_PATH"].presence || %w[google-chrome chromium chromium-browser].find { system("which", _1, out: File::NULL) }
    skip "Chrome isn't installed here" unless chrome
  end

  def render_text(paper)
    data = as_business(@business) { PdfRenderer.render(@quote.pdf_html, paper:, footer: @quote.pdf_footer) }
    reader = PDF::Reader.new(StringIO.new(data))
    [ reader, reader.pages.map(&:text).join("\n") ]
  end

  test "a long quote paginates on Letter, with every line, the totals, terms, status and page numbers" do
    reader, text = render_text(:letter)
    assert_operator reader.page_count, :>, 1
    assert_in_delta 612, reader.pages.first.attributes[:MediaBox][2], 1
    [ @business.name, "Quote #{@quote.number}", "Spring cleanup", "Maria Lopez", "12 Elm St", "Item 1", "Item 45", "Details for item 45",
      "Total", "$450.00", "Net 15.", "Draft", "Page 1 of #{reader.page_count}" ].each { assert_includes text, _1 }
    assert_not_includes text, "Gate code"
    # The column headers repeat on every page.
    reader.pages.each { assert_match(/Item\s+Qty\s+Price\s+Amount/, _1.text) }
  end

  test "a document can't reach the network or run scripts" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    hits = 0
    listener = Thread.new { loop { server.accept.close.then { hits += 1 } } }
    html = %(<html><head><link rel="prefetch" href="http://127.0.0.1:#{port}/p"><link rel="stylesheet" href="http://127.0.0.1:#{port}/s.css"></head>) +
           %(<body><img src="http://127.0.0.1:#{port}/i.png"><iframe src="http://127.0.0.1:#{port}/f"></iframe>) +
           %(<script>new WebSocket("ws://127.0.0.1:#{port}/w"); document.body.append("SCRIPT RAN")</script><p>Hello</p></body></html>)
    text = PDF::Reader.new(StringIO.new(PdfRenderer.render(html))).pages.map(&:text).join
    sleep 0.5
    assert_includes text, "Hello"
    assert_not_includes text, "SCRIPT RAN"
    assert_equal 0, hits
  ensure
    listener&.kill
    server&.close
  end

  test "a missing browser is a PdfRenderer::Error, so callers can explain it" do
    ENV["BROWSER_PATH"], previous = "/nonexistent/chrome", ENV["BROWSER_PATH"]
    assert_raises(PdfRenderer::Error) { PdfRenderer.render("<p>x</p>") }
  ensure
    ENV["BROWSER_PATH"] = previous
  end

  test "A4 for businesses outside the Letter countries" do
    @business.update!(country: "GB")
    @quote = as_business(@business) { @quote.reload }
    assert_equal :a4, as_business(@business) { @quote.pdf_paper }
    reader, = render_text(:a4)
    assert_in_delta 595, reader.pages.first.attributes[:MediaBox][2], 1
  end
end
