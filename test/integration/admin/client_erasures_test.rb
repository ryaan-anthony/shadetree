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

  test "their name is scrubbed from titles, lines, payments, sends, histories and other clients' notes; PDFs and revisions go" do
    other = nil
    as_business(@business) do
      @quote.reload.update!(title: "Cleanup for maria lopez")
      @quote.sync_line_items([ { "key" => "a", "name" => "Trim Maria's hedge", "description" => "Call (555) 010-0100 first", "quantity" => "1", "unit_price" => "300" } ])
      @quote.update!(tax_rates: [])
      @quote.mark_sent!(by: @owner, channel: "email", recipient: "maria@example.com", cc: "maria@example.com")
      @quote.current_pdf
      @quote.reload.revise!(by: @owner)
      @quote.reload.current_pdf
      @invoice.mark_sent!(by: @owner, channel: "link")
      @invoice.reload.record_payment!(by: @owner, amount: "10", received_on: @business.today, payment_method: "check", reference: "Lopez check", note: "From Maria")
      other = Client.create!(display_name: "Neighbor", notes: "Lives next to Maria Lopez at 12 Elm St",
                             contact_methods_attributes: [ { kind: "phone", value: "5550100777" } ])
      ClientNote.create!(client: other, user: @owner, body: "Text 555-010-0100 if gate locked; Maria is unrelated")
    end
    blob_ids = as_business(@business) { [ @quote.reload.pdf_blob_id, *@quote.revisions.map(&:pdf_blob_id) ].compact }
    assert_not_empty blob_ids

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { as_business(@business) { ClientErasure.new(@client, by: @owner).erase! } }

    as_business(@business) do
      @quote.reload
      assert_equal "Cleanup for [erased]", @quote.title
      assert_equal [ "Trim [erased]'s hedge", "Call [erased] first" ], @quote.line_items.first.slice(:name, :description).values
      assert_nil @quote.pdf_blob_id
      assert_empty ActiveStorage::Blob.where(id: blob_ids)
      @quote.revisions.each { |revision| assert_nil revision.pdf_blob_id; assert_no_match(/Maria|Lopez|Elm St|maria@/i, revision.snapshot.to_json) }
      @quote.sends.each { |send| assert_equal [ nil, nil ], [ send.recipient, send.cc ] }
      assert_no_match(/Maria|Lopez|maria@|0100/i, (@quote.events + @invoice.reload.events).map(&:data).to_json)
      @invoice.payments.each { |payment| assert_no_match(/Maria|Lopez/i, [ payment.note, payment.reference ].join) }
      assert_equal "Lives next to [erased] at [erased]", other.reload.notes
      assert_match(/Text \[erased\] if gate locked; Maria is unrelated/, other.timeline_notes.first.body, "a first name alone isn't scrubbed from other clients")
      assert_equal "cancelled", @visit.reload.status
    end
  end

  test "an erased client's documents can't be sent, answered or linked again" do
    as_business(@business) do
      @quote.reload.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "300" } ])
      @quote.update!(tax_rates: [])
      @quote.mark_sent!(by: @owner, channel: "link")
      ClientErasure.new(@client, by: @owner).erase!
      @quote.reload
      assert_not @quote.sendable?
      assert_not @invoice.reload.sendable?
      assert_raises(Quote::NotOpen) { @quote.record_response!(:approve, link: @link, signer_name: "X", terms_accepted: "1") }
      assert_raises(ArgumentError) { @quote.mark_sent!(by: @owner, channel: "link") }
      assert_raises(ClientLink::ClientErased) { @quote.client_link! }
      assert_raises(ClientLink::ClientErased) { @visit.reload.client_link! }
      assert_not ClientErasure.new(@client.reload, by: @owner).erase!, "a second erasure does nothing"
    end
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_redirected_to admin_quote_path(@quote)
    assert_equal "This client's details were erased, so nothing more can be sent to them.", flash[:alert]
  end

  test "another business's client isn't found" do
    theirs = as_business(businesses(:two)) { Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ]) }
    assert_not_found_across_businesses { post admin_client_erasure_path(theirs), params: { confirmation: "Theirs" } }
  end
end
