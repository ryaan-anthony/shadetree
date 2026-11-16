require "test_helper"

# QTE-06: the quote list, a sent quote's page and activity, archiving, duplicating, extending expiry.
class Admin::QuoteLifecycleTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @today = @business.today
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @sam = Client.create!(display_name: "Sam Okafor", contact_methods_attributes: [ { kind: "phone", value: "5550100299" } ])
      @draft = make_quote(@maria, "Spring cleanup", 100)
      @sent = make_quote(@maria, "Hedges", 200, status: "sent")
      @expired = make_quote(@sam, "Mulch", 300, status: "sent", expires_on: @today - 1)
      @approved = make_quote(@sam, "Patio", 400, status: "approved")
      @declined = make_quote(@maria, "Wall", 500, status: "sent")
      @declined.record_response!(:decline, message: "Went with a mason")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def make_quote(client, title, price, status: nil, expires_on: nil)
    quote = Quote.start(client:, created_by: users(:one))
    quote.title = title
    quote.sync_line_items([ { "key" => "a", "name" => title, "quantity" => "1", "unit_price" => price.to_s, "taxable" => "0" } ])
    quote.save!
    quote.update_columns(status:, sent_at: Time.current) if status
    quote.update_columns(expires_on:) if expires_on
    quote
  end

  def row_titles = css_select("tbody tr td:first-child a").map(&:text)

  test "only Owners and Admins see quotes, and another business's aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_quotes_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch archive_admin_quote_path(@sent) }
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get admin_quote_path(@sent) }
    assert_not_found_across_businesses { post duplicate_admin_quote_path(@sent) }
  end

  test "the list filters by status, with counts and totals for what's shown" do
    get admin_quotes_path
    assert_select "label.tab", /All\s*5/
    assert_select "label.tab", /Awaiting response\s*1/
    assert_select "label.tab", /Expired\s*1/
    assert_select "[role=status]", /5 quotes, \$1,500\.00/
    assert_equal [ "Wall", "Patio", "Mulch", "Hedges", "Spring cleanup" ], row_titles

    { "awaiting" => [ "Hedges" ], "expired" => [ "Mulch" ], "draft" => [ "Spring cleanup" ], "approved" => [ "Patio" ], "declined" => [ "Wall" ] }.each do |filter, titles|
      post search_admin_quotes_path, params: { filter: }
      assert_equal titles, row_titles, filter
    end
    post search_admin_quotes_path, params: { filter: "awaiting" }
    assert_select "[role=status]", /1 quote, \$200\.00/
    assert_select "tr", /Hedges.*Sent.*Not opened/m
    post search_admin_quotes_path, params: { filter: "declined" }
    assert_select "tr", /Wall.*Declined.*Went with a mason/m
  end

  test "search finds quotes by number or client, and stays out of the URL" do
    post search_admin_quotes_path, params: { q: "okafor" }
    assert_equal [ "Patio", "Mulch" ], row_titles
    post search_admin_quotes_path, params: { q: @sent.number }
    assert_equal [ "Hedges" ], row_titles
    post search_admin_quotes_path, params: { q: "nobody" }
    assert_select ".empty-title", "No quotes match"
  end

  test "a sent quote has its own page; a draft opens in the builder" do
    get admin_quote_path(@draft)
    assert_redirected_to edit_admin_quote_path(@draft)
    get admin_quote_path(@declined)
    assert_response :success
    assert_select "h1", "Wall"
    assert_select ".badge", "Declined"
    assert_select "#quote-activity li", /Declined by the client.*Went with a mason/m
    assert_select "#quote-activity li", /Created by #{users(:one).full_name}/
    assert_select ".quote-doc-lines", /Wall/
  end

  test "archiving hides a quote from the other tabs, and restoring brings it back" do
    patch archive_admin_quote_path(@approved)
    assert_redirected_to admin_quote_path(@approved)
    get admin_quotes_path
    assert_not_includes row_titles, "Patio"
    post search_admin_quotes_path, params: { filter: "archived" }
    assert_equal [ "Patio" ], row_titles
    get admin_quote_path(@approved)
    assert_select "#quote-activity li", /Archived by/

    patch unarchive_admin_quote_path(@approved)
    get admin_quotes_path
    assert_includes row_titles, "Patio"
  end

  test "duplicating makes a fresh draft, for the same client or another" do
    as_business(@business) { @sent.update!(message: "Thanks!", internal_notes: "Gate code 4") }
    post duplicate_admin_quote_path(@sent)
    copy = as_business(@business) { Quote.order(:id).last }
    assert_redirected_to edit_admin_quote_path(copy)
    as_business(@business) do
      assert_equal [ "draft", @maria.id, "Hedges", "Thanks!", "Gate code 4" ], [ copy.status, copy.client_id, copy.title, copy.message, copy.internal_notes ]
      assert_equal [ [ "Hedges", 20_000 ] ], copy.line_items.map { [ _1.name, _1.unit_price_cents ] }
      assert_not_equal @sent.number, copy.number
      assert_nil copy.sent_at
      assert_equal @sent.number, copy.events.sole.data["from"]
    end

    post duplicate_admin_quote_path(@sent), params: { client: @sam.uid }
    assert_equal @sam.id, as_business(@business) { Quote.order(:id).last.client_id }
    post duplicate_admin_quote_path(@sent), params: { client: "nobody" }
    assert_equal "Choose a client for the copy.", flash[:alert]
  end

  test "a sent or expired quote's valid-until date can be moved later, and it's recorded" do
    patch extend_expiry_admin_quote_path(@expired), params: { expires_on: (@today + 30).iso8601 }
    assert_redirected_to admin_quote_path(@expired)
    as_business(@business) do
      assert_equal @today + 30, @expired.reload.expires_on
      assert_not @expired.expired?
      assert_equal [ (@today - 1).iso8601, (@today + 30).iso8601 ], @expired.events.sole.data.values_at("from", "to")
    end

    patch extend_expiry_admin_quote_path(@sent), params: { expires_on: @today.iso8601 }
    assert_equal "Choose a date after today.", flash[:alert]
    patch extend_expiry_admin_quote_path(@approved), params: { expires_on: (@today + 30).iso8601 }
    assert_equal "Only a sent quote's expiry can be extended.", flash[:alert]
  end
end
