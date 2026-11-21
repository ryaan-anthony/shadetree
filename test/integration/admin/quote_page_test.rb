require "test_helper"

# QA #274 on the staff quote page: the client's IP address is evidence, never shown (owner
# decision 2026-11-21); one H1, with the quote document under it and its items a real table.
class Admin::QuotePageTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      quote = Quote.start(client: maria)
      quote.title = "Cricket in the basement"
      quote.terms = "Net 15."
      quote.sync_line_items([ { "key" => "a", "name" => "Inspection", "quantity" => "1", "unit_price" => "60", "taxable" => "0" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "link")
      quote
    end
    @link = as_business(@business) { @quote.client_link! }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "the client's IP address isn't on the page, but stays in the evidence and the export" do
    as_business(@business) do
      @quote.reload.record_response!(:approve, link: @link, signer_name: "Maria Lopez", terms_accepted: "1", ip_address: "2001:db8::7", device: "Computer · Chrome")
    end

    get admin_quote_path(@quote)
    assert_select "#responses-h", "Client response"
    assert_select "[id^=response-]", /From Computer · Chrome/
    assert_no_match "2001:db8::7", response.body

    approval = as_business(@business) { @quote.reload.approval }
    assert_equal "2001:db8::7", approval.ip_address
    assert approval.signature_valid?, "the IP is part of the signed evidence"

    get download_admin_data_exports_path("quote_responses")
    row = CSV.parse(response.body.delete_prefix("﻿"), headers: true).first
    assert_equal [ @quote.number, "Approved", "Maria Lopez", "2001:db8::7", approval.reference ],
                 row.values_at("Quote number", "Response", "Signed by", "IP address", "Reference")
  end

  test "the quote page has one H1; the document is an H2 with a real table of items, and the client page keeps its H1" do
    get admin_quote_path(@quote)
    assert_select "h1", count: 1
    assert_select ".quote-doc h2.quote-doc-title", "Cricket in the basement"
    assert_select ".quote-doc h3", "Terms"
    assert_select ".quote-doc table.quote-doc-lines thead th[scope=col]", 4
    assert_select ".quote-doc table.quote-doc-lines tbody tr", 1

    get client_link_path(@link.token)
    assert_select "h1.quote-doc-title", "Cricket in the basement"
    assert_select ".quote-doc h2", "Terms"
    assert_select "table.quote-doc-lines th[scope=col]", 4
  end
end
