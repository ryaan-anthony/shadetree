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
    patch status_admin_service_request_path(@service_request, status: "quoted")
    assert_response :unprocessable_content, "Quoted only comes from making a quote"

    post quote_admin_service_request_path(@service_request)
    quote = as_business(@business) { Quote.order(:id).last }
    assert_redirected_to edit_admin_quote_path(quote)
    as_business(@business) do
      assert_equal "quoted", @service_request.reload.status
      assert_equal @service_request, quote.service_request
      assert_equal @maria, quote.client
      assert_equal "12 Elm St", quote.property.address_line1, "a new typed address isn't added to the client"
      assert_equal [ "12 Elm St" ], @maria.properties.map(&:address_line1)
      assert_equal [ [ "Weekly mowing", "Mow and trim", 4_500 ] ], quote.line_items.map { [ _1.name, _1.description, _1.unit_price_cents ] }
      assert_equal 1, quote.attachments.count
    end
    follow_redirect!
    assert_select "a[href=?]", admin_service_request_path(@service_request), /request R-/
    assert_select "p", /They asked about.*9 Oak Ave, Austin.*isn't one of/m
    get admin_service_request_path(@service_request)
    assert_select "a", /#{quote.number}/
    # Every quote made from it is listed.
    post quote_admin_service_request_path(@service_request)
    assert_equal 2, as_business(@business) { @service_request.quotes.count }

    # With every quote deleted, it's back in progress.
    as_business(@business) { @service_request.quotes.each(&:destroy!) }
    assert_equal "in_progress", as_business(@business) { @service_request.reload.status }
  end

  test "a sent quote's page links back to its request (QTE-06)" do
    post quote_admin_service_request_path(@service_request)
    quote = as_business(@business) { Quote.order(:id).last.tap { _1.update_columns(status: "sent", sent_at: Time.current) } }
    get admin_quote_path(quote)
    assert_response :success
    assert_select "a[href=?]", admin_service_request_path(@service_request), /request #{@service_request.reference}/
    assert_select "p", { text: /They asked about/, count: 0 }, "the address note is for drafts, where the property can still change"
  end

  test "an archived client's request can't be quoted until they're restored" do
    as_business(@business) { @maria.archive! }
    post quote_admin_service_request_path(@service_request)
    assert_match "is archived", flash[:alert]
    assert_equal 0, as_business(@business) { Quote.count }
  end

  test "hovering a request (Turbo's prefetch) doesn't count as seeing it" do
    get admin_service_request_path(@service_request), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_empty as_business(@business) { @service_request.views.to_a }
  end

  test "staff log a request from a call, with the client and services" do
    get new_admin_service_request_path
    assert_response :success
    hidden = as_business(@business) { CatalogItem.create!(name: "Snow removal", unit: "visit", show_on_request_form: false) }
    property = as_business(@business) { @maria.properties.sole }
    post admin_service_requests_path, params: { service_request: { client: @maria.uid, property: property.uid, source: "phone",
                                                                   description: "Called about mowing", service_ids: [ @mowing.uid, hidden.uid ] } }
    logged = as_business(@business) { ServiceRequest.order(:id).last }
    assert_redirected_to admin_service_request_path(logged)
    assert_equal [ "phone", "new", users(:one).id, [ "Weekly mowing", "Snow removal" ], @maria.id, property.id ],
                 [ logged.source, logged.status, logged.created_by_id, logged.service_names, logged.client_id, logged.property_id ]
    get new_admin_service_request_path
    assert_select "select[name='service_request[property]']"
    get property_options_admin_quotes_path(client: @maria.uid, name: "service_request[property]")
    assert_select "select[name='service_request[property]'] option", /12 Elm St/

    post admin_service_requests_path, params: { service_request: { client: "", source: "phone", description: "" } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Choose a client, or add a new one\./
    post admin_service_requests_path, params: { service_request: { client: @maria.uid, source: "phone", description: "" } }
    assert_select ".error-text", "Say what they need."
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
