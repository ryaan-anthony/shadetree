require "test_helper"

# INS-02: erasing a client's personal data, keeping the financial records.
class Admin::ClientErasuresTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    as_business(@business) do
      @client = Client.create!(display_name: "Maria Lopez", company_name: "Lopez Bakery", notes: "Allergic to bees", tags: %w[vip],
                               contact_methods_attributes: [ { kind: "email", value: "maria@example.com" }, { kind: "phone", value: "5550100100" } ],
                               properties_attributes: [ { address_line1: "12 Elm St", city: "Asheville", region: "NC", postal_code: "28801", access_notes: "Gate 4411", billing: true } ])
      ClientNote.create!(client: @client, user: @owner, body: "Maria prefers mornings")
      @quote = Quote.create!(client: @client, property: @client.properties.first, created_by: @owner, title: "Spring cleanup", internal_notes: "Maria's sister referred her")
      @quote.attachments.attach(io: StringIO.new("%PDF-1.4 x\n%%EOF\n"), filename: "yard.pdf", content_type: "application/pdf")
      @invoice = Invoice.start(client: @client)
      @invoice.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "120" } ])
      @invoice.update!(tax_rates: [], message: "Thanks Maria!")
      @link = ClientLink.issue!(@quote, actions: %w[approve])
      job = Job.create!(client: @client, property: @client.properties.first, title: "Mowing", instructions: "Ring Maria at 12 Elm St")
      @visit = job.visits.new(scheduled_on: @business.today + 1, timing: "anytime", duration_minutes: 60).tap { _1.schedule!(by: @owner) }
      @visit.photos.attach(io: StringIO.new("jpeg"), filename: "yard.jpg", content_type: "image/jpeg")
      @export = DataExport.create!(kind: "full", status: "ready", expires_at: 1.day.from_now, requested_by: @owner,
                                   files: [ { io: StringIO.new("PK"), filename: "x.zip", content_type: "application/zip" } ])
    end
  end

  test "Owners and Admins erase; technicians can't" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_client_erasure_path(@client) }
  end

  test "it asks for the client's name, then erases their details everywhere and keeps the money" do
    get admin_client_path(@client)
    assert_select "a[href=?]", new_admin_client_erasure_path(@client)
    get new_admin_client_erasure_path(@client)
    assert_select "label", /Type Maria Lopez to confirm/
    post admin_client_erasure_path(@client), params: { confirmation: "maria" }
    assert_response :unprocessable_content
    assert_not as_business(@business) { @client.reload.erased? }

    post admin_client_erasure_path(@client), params: { confirmation: " maria lopez " }
    assert_redirected_to admin_client_path(@client)
    as_business(@business) do
      @client.reload
      assert @client.erased?
      assert_equal [ "Erased client", nil, nil, [] ], [ @client.display_name, @client.company_name, @client.notes, @client.tags ]
      assert_empty @client.contact_methods
      assert_empty @client.timeline_notes
      assert_equal [ "Erased address", nil, nil ], @client.properties.first.slice(:address_line1, :city, :access_notes).values
      assert_equal [ 12_000, nil, nil ], [ @invoice.reload.total_cents, @invoice.message, @quote.reload.internal_notes ]
      assert_not @quote.attachments.attached?
      assert_not @visit.reload.photos.attached?
      assert @link.reload.revoked_at
      assert_equal "expired", @export.reload.status
      assert DataExport.exists?(kind: "client_erased", requested_by: @owner)
      assert_empty Client.search("Maria")
      assert_empty Client.matching(emails: [ "maria@example.com" ], phones: [ "5550100100" ])
    end

    get admin_client_path(@client)
    assert_select "#erased-banner"
    get edit_admin_client_path(@client)
    assert_redirected_to admin_client_path(@client)

    texts = DataExport::TABLES.each_key.map do |key|
      get download_admin_data_exports_path(key)
      response.body
    end.join
    assert_no_match(/Maria|Lopez|maria@example|5550100100|Elm St|Gate 4411|Allergic|bees|sister/i, texts, "no personal data in any export")
  end

  test "a signed approval is kept as what was agreed, and still verifies" do
    as_business(@business) do
      @quote.reload.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "300" } ])
      @quote.update!(tax_rates: [])
      @quote.mark_sent!(by: @owner, channel: "link")
      @quote.reload.record_response!(:approve, link: @link, signer_name: "Maria Lopez", email: "maria@example.com", ip_address: "203.0.113.5", terms_accepted: "1")
    end
    as_business(@business) { ClientErasure.new(@client, by: @owner).erase! }
    response = as_business(@business) { @quote.reload.responses.first }
    assert_equal [ "Erased client", nil, nil ], [ response.signer_name, response.email, response.ip_address ]
    assert response.signature_valid?
    assert response.snapshot_intact?
    assert_no_match(/Maria|Elm St/, response.snapshot.to_json)
  end

  test "another business's client isn't found" do
    theirs = as_business(businesses(:two)) { Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ]) }
    assert_not_found_across_businesses { post admin_client_erasure_path(theirs), params: { confirmation: "Theirs" } }
  end
end
