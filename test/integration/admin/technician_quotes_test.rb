require "test_helper"

# QTE-07: members whose role lets them quote the requests given to them build, preview and
# download their own drafts, with catalog prices, and nothing else in the office.
class Admin::TechnicianQuotesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15)
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @senior = as_business(@business) { Role.create!(name: "Senior tech", permissions: %w[field_work quote_requests]) }
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "custom", role_id: @senior.id)
    as_business(@business) do
      @mowing = CatalogItem.create!(name: "Weekly mowing", unit: "visit", unit_price: "45")
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", billing: true } ])
      @request_record = ServiceRequest.create!(client: @maria, source: "phone", description: "Mowing", services: [ { "catalog_item_id" => @mowing.id, "name" => "Weekly mowing" } ])
      RequestFollowUp.assign!(@request_record, { user: @tech, scheduled_on: Date.new(2026, 11, 23) }, by: @owner).done!(by: @tech)
      @office_quote = Quote.start(client: @maria, created_by: @owner)
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def quote_it
    post quote_admin_my_request_path(@request_record)
    as_business(@business) { Quote.order(:id).last }
  end

  def builder_params(quote, lines: [], **fields)
    { quote: { lock_version: quote.lock_version, lines_present: "1", lines: lines.each_with_index.to_h { |line, index| [ index.to_s, line ] }, **fields } }
  end

  test "from a done follow-up they create the quote, pre-filled as from the inbox, and it's theirs" do
    get admin_my_request_path(@request_record)
    assert_select "form[action=?] button", quote_admin_my_request_path(@request_record), /Create quote/
    quote = quote_it
    assert_redirected_to edit_admin_quote_path(quote)
    assert_match "Nothing is sent until the office sends it", flash[:notice]
    as_business(@business) do
      assert_equal [ @tech, @request_record, @maria ], [ quote.created_by, quote.service_request, quote.client ]
      assert_equal [ [ "Weekly mowing", 4_500 ] ], quote.line_items.map { [ _1.name, _1.unit_price_cents ] }
      assert_equal "quoted", @request_record.reload.status
    end
    get admin_my_day_path
    assert_select "#my-quote-drafts a[href=?]", edit_admin_quote_path(quote), /Maria Lopez/
  end

  test "they build their draft with catalog prices, but can't change its client, send it or delete it" do
    quote = quote_it
    get edit_admin_quote_path(quote)
    assert_response :success
    assert_select "input[name='quote[client]']", 0, "no client picker"
    assert_select "p", /From the request you followed up/
    assert_select "a[href=?]", new_admin_quote_send_path(quote), 0
    assert_select "form[action=?][method=post] input[value=delete]", admin_quote_path(quote), 0
    assert_select "a[href=?]", admin_service_request_path(@request_record), 0
    get search_admin_catalog_items_path(format: :json, q: "mow")
    assert_response :success
    assert_equal [ "Weekly mowing" ], response.parsed_body["items"].map { _1["name"] }

    other = as_business(@business) { Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5125550101" } ]) }
    patch admin_quote_path(quote), params: builder_params(quote, client: other.uid, title: "Weekly mowing, from May",
                                                                 lines: [ { key: "k1", name: "Weekly mowing", quantity: "20", unit_price: "45", taxable: "0" } ]), as: :turbo_stream
    assert_response :success
    as_business(@business) do
      quote.reload
      assert_equal [ @maria, "Weekly mowing, from May", BigDecimal(20) ], [ quote.client, quote.title, quote.line_items.sole.quantity ]
    end
    get preview_admin_quote_path(quote)
    assert_response :success
    get pdf_admin_quote_path(quote)
    assert_response :success
  end

  test "only their own drafts from requests, only until sent; nothing else in the office" do
    quote = quote_it
    get edit_admin_quote_path(@office_quote)
    assert_response :not_found
    patch admin_quote_path(@office_quote), params: builder_params(@office_quote, title: "x"), as: :turbo_stream
    assert_response :not_found
    [ admin_quotes_path, admin_service_requests_path, admin_clients_path, admin_invoices_path, admin_client_path(@maria) ].each do |path|
      get path
      assert_response :forbidden, path
    end
    delete admin_quote_path(quote)
    assert_response :forbidden, "deleting isn't theirs"

    as_business(@business) { quote.update_columns(status: "sent") }
    get edit_admin_quote_path(quote)
    assert_response :not_found, "once sent, it's the office's"

    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get edit_admin_quote_path(@office_quote) }
  end

  test "without the permission, a technician can't quote, build or search the catalog" do
    tech = member_with_role(:technician)
    as_business(@business) do
      @request_record.follow_up.update_columns(user_id: tech.id)
    end
    sign_in tech
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_request_path(@request_record)
    assert_select "form[action=?]", quote_admin_my_request_path(@request_record), 0
    post quote_admin_my_request_path(@request_record)
    assert_response :forbidden
    get edit_admin_quote_path(@office_quote)
    assert_response :forbidden
    get search_admin_catalog_items_path(format: :json)
    assert_response :forbidden
  end

  test "Owners and Admins have both new permissions; a custom role can be given them" do
    assert Permissions.granted?("admin", :quote_requests)
    assert Permissions.granted?("admin", :send_own_quotes)
    assert_not Permissions.granted?("technician", :quote_requests)
    assert_includes Permissions::GRANTABLE, :send_own_quotes
  end
end
