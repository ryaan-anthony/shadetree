require "test_helper"

# QTE-03: the client's quote page, reached through a client link (PLT-12).
class Client::QuotePageTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com", phone: "555-380-0000")
    @quote = as_business(@business) do
      TaxRate.create!(name: "State", percent: "6.25")
      maria = Client.create!(display_name: "Maria Lopez", company_name: "Lopez Rentals", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                             properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", billing: true } ])
      quote = Quote.start(client: maria)
      quote.assign_attributes(title: "Spring cleanup", message: "Thanks for having us out.", internal_notes: "Gate code 1234", terms: "Net 15.")
      quote.sync_line_items([
        { "key" => "a", "name" => "Leaf cleanup", "description" => "Front and back yards", "quantity" => "1", "unit_price" => "180", "taxable" => "1",
          "discount_kind" => "percent", "discount_value" => "10" },
        { "key" => "b", "name" => "Mulch", "quantity" => "4", "unit" => "bag", "unit_price" => "8.50", "taxable" => "1" }
      ])
      quote.attach_files([ Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png", original_filename: "yard.png") ])
      quote.save!
      quote.update_column(:status, "sent")
      quote
    end
    @link = as_business(@business) { ClientLink.issue!(@quote) }
  end

  def set_quote(**attributes) = as_business(@business) { @quote.update_columns(**attributes) }

  test "shows everything the client needs, and none of the internal notes" do
    get client_link_path(@link.token)
    assert_response :success
    assert_select "header.client-head", /#{@business.name}/
    assert_select ".quote-doc-title", "Spring cleanup"
    assert_select ".quote-doc-kicker", "Quote #{@quote.number}"
    assert_select ".quote-doc-meta", /Maria Lopez.*Lopez Rentals.*12 Elm St.*Valid until/m
    assert_select ".quote-doc-message", "Thanks for having us out."
    assert_select ".quote-doc-lines tbody tr", 2
    assert_select ".quote-doc-line-description", "Front and back yards"
    assert_select ".quote-doc-line-discount", /\$18\.00 off \(10%\)/
    assert_select ".quote-doc-lines", /4.*bag.*\$8\.50.*\$34\.00/m
    assert_select "#quote_totals", /Subtotal.*\$196\.00.*State \(6\.25%\).*\$12\.25.*Total.*\$208\.25/m
    assert_select ".quote-doc-terms", /Net 15\./
    assert_select "img[alt=yard][loading=lazy]"
    assert_select "#quote-actions", /Total \$208\.25.*Valid until/m
    assert_select "a[href='tel:555-380-0000']"
    assert_no_match "Gate code 1234", response.body
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "views are recorded; staff preview isn't one" do
    get client_link_path(@link.token)
    get client_link_path(@link.token)
    assert_equal 2, as_business(@business) { @link.reload.views_count }

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get preview_admin_quote_path(@quote)
    assert_select ".banner", /Preview/
    assert_select ".quote-doc-title", "Spring cleanup"
    assert_equal 2, as_business(@business) { @link.reload.views_count }
  end

  test "staff previewing a link get staff routes for files and the PDF, and no client actions" do
    set_quote(expires_on: @business.today - 1)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get preview_admin_client_link_path(@link)
    assert_response :success
    assert_select "a[href=?]", pdf_admin_quote_path(@quote), /Download PDF/
    assert_no_match %r{/c/#{@link.token}/}, response.body
    assert_select "form[action=?]", request_quote_update_path(@link.token), count: 0
  end

  test "sent quotes open in the read-only preview from the quotes list and the client page; drafts in the builder" do
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_quotes_path
    assert_select "a[href=?]", preview_admin_quote_path(@quote), @quote.number
    get admin_client_path(@quote.client)
    assert_select "a[href=?]", preview_admin_quote_path(@quote)
    set_quote(status: "draft")
    get admin_quotes_path
    assert_select "a[href=?]", edit_admin_quote_path(@quote), @quote.number
  end

  test "staff can preview a draft, but a client link never shows one" do
    set_quote(status: "draft")
    get client_link_path(@link.token)
    assert_response :gone
    assert_no_match "Spring cleanup", response.body
    assert_equal 0, as_business(@business) { @link.reload.views_count }

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get preview_admin_quote_path(@quote)
    assert_select ".quote-doc-title", "Spring cleanup"
  end

  test "each state says where things stand" do
    { "approved" => /You approved this quote/, "declined" => /You declined this quote/, "changes_requested" => /You asked for changes/ }.each do |status, text|
      set_quote(status:)
      get client_link_path(@link.token)
      assert_select ".banner", text, status
    end
  end

  test "photos and files are served through the link, and stop when it's revoked" do
    get client_link_path(@link.token)
    photo = as_business(@business) { @quote.attachments_attachments.first }
    assert_select "img[src=?]", client_quote_file_path(@link.token, photo, size: "web")
    assert_select "a[href=?]", client_quote_file_path(@link.token, photo)
    assert_no_match %r{/rails/active_storage/}, response.body

    get client_quote_file_path(@link.token, photo)
    assert_response :redirect
    assert_match %r{/rails/active_storage/disk/}, response.location
    get client_quote_file_path(@link.token, photo, size: "web")
    assert_response :redirect

    other = as_business(@business) do
      Quote.start(client: @quote.client).tap { _1.attach_files([ Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png") ]); _1.save! }
    end
    get client_quote_file_path(@link.token, as_business(@business) { other.attachments_attachments.first })
    assert_response :not_found, "another quote's file isn't reachable through this link"

    as_business(@business) { @link.revoke! }
    get client_quote_file_path(@link.token, photo)
    assert_response :gone
  end

  test "an expired quote can be viewed, not approved, and the client can ask for an updated one once" do
    set_quote(expires_on: @business.today - 1) # the business's date, not UTC's
    get client_link_path(@link.token)
    assert_select ".banner-warning", /expired on/
    assert_select "#quote-actions", /This quote has expired/

    lock_version = as_business(@business) { @quote.reload.lock_version }
    post request_quote_update_path(@link.token)
    assert_redirected_to client_link_path(@link.token)
    follow_redirect!
    assert_select ".banner-warning", /You asked for an updated quote/
    requested_at = as_business(@business) { @quote.reload.update_requested_at }
    assert requested_at

    travel 2.hours do
      post request_quote_update_path(@link.token)
      assert_redirected_to client_link_path(@link.token)
      assert_match "You've already asked", flash[:notice]
    end
    assert_equal requested_at, as_business(@business) { @quote.reload.update_requested_at }
    assert_equal 1, as_business(@business) { @link.events.where(kind: "quote_update_requested").count }
    assert_equal lock_version, as_business(@business) { @quote.reload.lock_version }, "staff editing isn't interrupted"

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_quotes_path
    assert_select "tr", /#{@quote.number}.*Sent.*Update requested/m
  end

  test "a quote that hasn't expired can't be marked as needing an update" do
    post request_quote_update_path(@link.token)
    assert_redirected_to client_link_path(@link.token)
    assert_nil flash[:notice]
    assert_nil as_business(@business) { @quote.reload.update_requested_at }
    assert_equal 0, as_business(@business) { @link.events.where(kind: "quote_update_requested").count }
  end

  test "an update can't be asked for through a revoked, expired or unknown link, or for a draft" do
    set_quote(expires_on: @business.today - 1) # the business's date, not UTC's
    as_business(@business) { @link.update_columns(expires_at: 1.minute.ago) }
    post request_quote_update_path(@link.token)
    assert_response :gone

    as_business(@business) { @link.update_columns(expires_at: 1.day.from_now) }
    as_business(@business) { @link.revoke! }
    post request_quote_update_path(@link.token)
    assert_response :gone

    assert_not_found_across_businesses { post request_quote_update_path("1" * ClientLink::TOKEN_LENGTH) }
    assert_not_found_across_businesses { post request_quote_update_path("not-a-token") }

    fresh = as_business(@business) { ClientLink.issue!(@quote) }
    set_quote(status: "draft")
    assert_not_found_across_businesses { post request_quote_update_path(fresh.token) }
    assert_nil as_business(@business) { @quote.reload.update_requested_at }
  end

  test "links are isolated: a revoked link, a wrong token or another business's link shows nothing of this quote" do
    as_business(@business) { @link.revoke! }
    get client_link_path(@link.token)
    assert_response :gone
    assert_no_match "Spring cleanup", response.body

    get client_link_path("1" * ClientLink::TOKEN_LENGTH)
    assert_response :not_found

    other = as_business(businesses(:two)) do
      theirs = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      ClientLink.issue!(Quote.start(client: theirs).tap { _1.update_column(:status, "sent") })
    end
    get client_link_path(other.token)
    assert_response :success
    assert_no_match "Spring cleanup", response.body
    assert_no_match @business.name, response.body
  end
end
