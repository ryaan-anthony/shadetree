require "test_helper"

# QTE-06 (part 2): revising a sent quote, what the client sees meanwhile, and past revisions.
class Admin::QuoteRevisionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client: maria, created_by: users(:one)).tap do
        _1.title = "Fall cleanup"
        _1.sync_line_items([ { "key" => "a", "name" => "Leaf removal", "quantity" => "1", "unit_price" => "200", "taxable" => "0" },
                             { "key" => "b", "name" => "Side yard edging", "quantity" => "90", "unit_price" => "2.25", "taxable" => "0" } ])
        _1.save!
        _1.mark_sent!(by: users(:one), channel: "link")
      end
    end
    @link = as_business(@business) { @quote.client_link! }
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def fresh = as_business(@business) { @quote.reload }

  def revise
    with_fake_pdf_renderer { post revise_admin_quote_path(@quote) }
  end

  # The builder's save, with every line, as the form sends it.
  def save_lines(lines)
    patch admin_quote_path(@quote), params: { quote: { lock_version: fresh.lock_version, lines_present: "1",
                                                       lines: lines.each_with_index.to_h { |line, i| [ i.to_s, line ] } } }
  end

  test "only Owners and Admins can revise, and only their own business's quotes" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { post revise_admin_quote_path(@quote) }
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { post revise_admin_quote_path(@quote) }
  end

  test "revising keeps what the client was sent and reopens the quote in the builder" do
    as_business(@business) { @quote.record_response!(:request_changes, link: @link, message: "Skip the side yard") }
    revise
    assert_redirected_to edit_admin_quote_path(@quote)
    follow_redirect!
    assert_select ".page-lede", /Revision 2 for Maria Lopez/

    quote = fresh
    assert_equal [ "draft", 2 ], [ quote.status, quote.revision ]
    assert quote.editable?
    revision = as_business(@business) { quote.revisions.sole }
    assert_equal [ 1, "changes_requested", 40_250 ], [ revision.number, revision.status, revision.snapshot.dig("totals", "total_cents") ]
    assert revision.pdf_blob, "the PDF the client got is kept"
    assert_nil quote.pdf_blob_id
  end

  test "while it's being revised the client sees that, not the unfinished edits, and can't answer or download" do
    revise
    save_lines([ { key: "a", name: "Leaf removal", quantity: "1", unit_price: "200", taxable: "0" } ])
    get client_link_path(@link.token)
    assert_response :success
    assert_select "h1", "#{@business.name} is updating this quote"
    assert_no_match "Leaf removal", response.body
    get client_quote_pdf_path(@link.token)
    assert_redirected_to client_link_path(@link.token)
    post approve_client_quote_path(@link.token), params: { version: fresh.lock_version, quote_response: { signer_name: "Maria", terms_accepted: "1" } }
    assert_equal "#{@business.name} is updating this quote. You'll get the new version soon.", flash[:alert]
  end

  test "sending the revision shows the client the latest, refuses the old page, and counts no new usage" do
    old_version = fresh.lock_version
    revise
    save_lines([ { key: "a", name: "Leaf removal", quantity: "1", unit_price: "200", taxable: "0" } ])
    post admin_quote_send_path(@quote), params: { channel: "link" }

    quote = fresh
    assert_equal [ "sent", 2 ], [ quote.status, quote.revision ]
    assert_equal [ 1, 2 ], as_business(@business) { quote.sends.map(&:revision).sort }
    assert_equal 1, as_business(@business) { UsageEvent.where(subject: quote).count }

    get client_link_path(@link.token)
    assert_select ".quote-doc-lines tbody tr", 1
    assert_no_match "Side yard edging", response.body
    # A page opened on revision 1 can't approve revision 2.
    post approve_client_quote_path(@link.token), params: { version: old_version, quote_response: { signer_name: "Maria", terms_accepted: "1" } }
    assert_equal "This quote was updated after you opened it. Check this version, then approve again.", flash[:alert]

    get admin_quote_path(@quote)
    assert_select "#quote-revisions", /Rev 2.*Current.*Rev 1.*superseded/m
    assert_select "#quote-activity li", /Revision 2 sent as a link/
    assert_select "#quote-activity li", /Revision 2 started by/
  end

  test "a previous revision shows what was sent and what changed next" do
    revise
    save_lines([ { key: "a", name: "Leaf removal", quantity: "2", unit_price: "200", taxable: "0" },
                 { key: "c", name: "Gutter clean", quantity: "1", unit_price: "80", taxable: "0" } ])
    get revision_admin_quote_path(@quote, number: 1)
    assert_response :success
    assert_select "td", /Side yard edging/
    changes = css_select("#revision-changes li").map(&:text)
    assert_equal [ "Removed Side yard edging", "Added Gutter clean", "Leaf removal: quantity 1 → 2", "Total $402.50 → $480.00" ], changes
    get revision_admin_quote_path(@quote, number: 9)
    assert_response :not_found
  end

  test "an expired quote reopens by revising, with a fresh valid-until date, answering the update request" do
    as_business(@business) { @quote.update_columns(expires_on: @business.today - 3, update_requested_at: Time.current) }
    revise
    quote = fresh
    assert_equal @business.today + @business.quote_expiry_days, quote.expires_on
    assert_nil quote.update_requested_at
    assert_equal "expired", as_business(@business) { quote.revisions.sole.status }
  end

  test "approved, draft and archived quotes can't be revised, and a revision in progress can't be deleted" do
    as_business(@business) { @quote.update_columns(status: "approved") }
    revise
    assert_equal "Quote #{@quote.number} can't be revised.", flash[:alert]
    get admin_quote_path(@quote)
    assert_select "button", { text: /Revise/, count: 0 }

    as_business(@business) { @quote.update_columns(status: "sent", archived_at: Time.current) }
    revise
    assert_equal "Quote #{@quote.number} can't be revised.", flash[:alert]

    as_business(@business) { @quote.update_columns(archived_at: nil) }
    revise
    delete admin_quote_path(@quote)
    assert_equal "Only quotes that were never sent can be deleted.", flash[:alert]
    assert fresh
  end
end
