require "test_helper"

# CLI-04: the request inbox, logging a request, notes, statuses and quotes from requests.
class Admin::RequestInboxTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    as_business(@business) do
      @mowing = CatalogItem.create!(name: "Weekly mowing", unit: "visit", unit_price: "45", show_on_request_form: true, description: "Mow and trim")
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", billing: true } ])
      @service_request = ServiceRequest.create!(client: @maria, source: "form", description: "Front and back", timing: "As soon as possible",
                                        services: [ { "catalog_item_id" => @mowing.id, "name" => "Weekly mowing" } ],
                                        contact_name: "Maria Lopez", contact_phone: "5550100100", matched_existing_client: true,
                                        address: { "address_line1" => "9 Oak Ave", "city" => "Austin" })
      @service_request.photos.attach(io: file_fixture("logo.png").open, filename: "yard.png", content_type: "image/png")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "only Owners and Admins see requests, and another business's aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_service_requests_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post quote_admin_service_request_path(@service_request) }
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get admin_service_request_path(@service_request) }
    assert_not_found_across_businesses { patch status_admin_service_request_path(@service_request, status: "archived") }
    assert_not_found_across_businesses { post admin_service_request_notes_path(@service_request), params: { service_request_note: { body: "x" } } }
  end

  test "the inbox lists new requests with a count in the navigation" do
    get admin_service_requests_path
    assert_select ".side-link", /Requests\s*1/
    assert_select "nav.tabs a[aria-current=page]", /New\s*1/
    assert_select "#request-#{@service_request.uid}", /Maria Lopez.*Weekly mowing.*Front and back.*Request form.*1 photo.*9 Oak Ave/m
    assert_select "#request-#{@service_request.uid} .sr-only", /Not opened by you/
  end

  test "opening a request shows everything and records who saw it" do
    get admin_service_request_path(@service_request)
    assert_response :success
    assert_select "dd", "5550100100"
    assert_select "dd", "9 Oak Ave, Austin"
    assert_select "dd", "Weekly mowing"
    assert_select "img[alt=?]", "Photo 1 from Maria Lopez"
    assert_select "p", /Matched to Maria Lopez/
    assert_select "aside li", /#{users(:one).full_name}/
    assert_equal [ users(:one).id ], as_business(@business) { @service_request.views.pluck(:user_id) }

    get admin_service_requests_path
    assert_select "#request-#{@service_request.uid} .sr-only", false
    get admin_service_request_path(@service_request)
    assert_equal 1, as_business(@business) { @service_request.views.count }
  end

  test "statuses change by hand, and creating a quote marks it quoted" do
    patch status_admin_service_request_path(@service_request, status: "in_progress")
    assert_equal "in_progress", as_business(@business) { @service_request.reload.status }
    patch status_admin_service_request_path(@service_request, status: "bogus")
    assert_response :unprocessable_content

    post quote_admin_service_request_path(@service_request)
    quote = as_business(@business) { Quote.order(:id).last }
    assert_redirected_to edit_admin_quote_path(quote)
    as_business(@business) do
      assert_equal "quoted", @service_request.reload.status
      assert_equal @service_request, quote.service_request
      assert_equal @maria, quote.client
      assert_equal "9 Oak Ave", quote.property.address_line1, "the typed address becomes a property once staff act on it"
      assert_not quote.property.billing
      assert_equal [ [ "Weekly mowing", "Mow and trim", 4_500 ] ], quote.line_items.map { [ _1.name, _1.description, _1.unit_price_cents ] }
      assert_equal 1, quote.attachments.count
    end
    follow_redirect!
    assert_select "a[href=?]", admin_service_request_path(@service_request), /request R-/
    get admin_service_request_path(@service_request)
    assert_select "a", /#{quote.number}/
    # Every quote made from it is listed.
    post quote_admin_service_request_path(@service_request)
    assert_equal 2, as_business(@business) { @service_request.quotes.count }
  end

  test "staff log a request from a call, with the client and services" do
    get new_admin_service_request_path
    assert_response :success
    post admin_service_requests_path, params: { service_request: { client: @maria.uid, source: "phone", description: "Called about mowing", service_ids: [ @mowing.uid ] } }
    logged = as_business(@business) { ServiceRequest.order(:id).last }
    assert_redirected_to admin_service_request_path(logged)
    assert_equal [ "phone", "new", users(:one).id, [ "Weekly mowing" ], @maria.id ],
                 [ logged.source, logged.status, logged.created_by_id, logged.service_names, logged.client_id ]

    post admin_service_requests_path, params: { service_request: { client: "", source: "phone", description: "" } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Choose a client, or add a new one\./
  end

  test "internal notes are added with who wrote them" do
    post admin_service_request_notes_path(@service_request), params: { service_request_note: { body: "Gate code 1234" } }
    get admin_service_request_path(@service_request)
    assert_select "#notes li", /Gate code 1234.*#{users(:one).full_name}/m
    post admin_service_request_notes_path(@service_request), params: { service_request_note: { body: " " } }
    assert_equal "Write something before adding the note.", flash[:alert]
  end

  test "requests appear on the client's page" do
    get admin_client_path(@maria)
    assert_select "a[href=?]", admin_service_request_path(@service_request), /Request R-.*Weekly mowing/
  end
end
