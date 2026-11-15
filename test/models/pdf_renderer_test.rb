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

  def render_text(paper)
    data = as_business(@business) { PdfRenderer.render(@quote.pdf_html, paper:, footer: @quote.pdf_footer) }
    reader = PDF::Reader.new(StringIO.new(data))
    [ reader, reader.pages.map(&:text).join("\n") ]
  rescue PdfRenderer::Error, Ferrum::BinaryNotFoundError => error
    skip "Chrome isn't available here (#{error.class})"
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

  test "A4 for businesses outside the Letter countries" do
    @business.update!(country: "GB")
    @quote = as_business(@business) { @quote.reload }
    assert_equal :a4, as_business(@business) { @quote.pdf_paper }
    reader, = render_text(:a4)
    assert_in_delta 595, reader.pages.first.attributes[:MediaBox][2], 1
  end
end
