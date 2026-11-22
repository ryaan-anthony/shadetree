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

  test "Owners and Admins can quote assigned requests; a custom role can be given it, Technicians can't by default" do
    assert Permissions.granted?("admin", :quote_requests)
    assert_not Permissions.granted?("technician", :quote_requests)
    assert_includes Permissions::GRANTABLE, :quote_requests
  end

  test "once the office has sent it, it's not theirs again, even when revised back to a draft" do
    quote = quote_it
    patch admin_quote_path(quote), params: builder_params(quote, lines: [ { key: "k1", name: "Weekly mowing", quantity: "1", unit_price: "45", taxable: "0" } ]), as: :turbo_stream
    as_business(@business) do
      quote.reload.mark_sent!(by: @owner, channel: "link")
      quote.reload.revise!(by: @owner)
      assert_equal [ "draft", 2 ], [ quote.reload.status, quote.revision ]
    end
    get edit_admin_quote_path(quote)
    assert_response :not_found
    patch admin_quote_path(quote), params: builder_params(quote, title: "Sneaky"), as: :turbo_stream
    assert_response :not_found
    get admin_my_day_path
    assert_select "#my-quote-drafts", 0
  end

  test "another member's draft, and its files and prices, are out of reach" do
    other = User.create!(email: "tia@example.com", password: "password123", first_name: "Tia", confirmed_at: Time.current)
    BusinessUser.create!(user: other, business: @business, role: "custom", role_id: @senior.id)
    theirs = as_business(@business) do
      request = ServiceRequest.create!(client: @maria, source: "phone", description: "Hedges")
      RequestFollowUp.assign!(request, { user: other, scheduled_on: Date.new(2026, 11, 23) }, by: @owner).done!(by: other)
      request.create_quote!(by: other).tap { _1.attachments.attach(io: file_fixture("logo.png").open, filename: "plan.png", content_type: "image/png") }
    end
    get edit_admin_quote_path(theirs)
    assert_response :not_found
    delete admin_quote_attachment_path(theirs, as_business(@business) { theirs.attachments.first.id })
    assert_response :not_found
    patch reprice_admin_quote_path(theirs)
    assert_response :not_found
  end

  test "from a follow-up, a second click (checked under the lock) doesn't make a second draft; the inbox still may" do
    quote = as_business(@business) { @request_record.create_quote!(by: @tech, once: true) }
    error = assert_raises(ServiceRequest::AlreadyQuoted) { as_business(@business) { @request_record.reload.create_quote!(by: @tech, once: true) } }
    assert_equal quote, error.quote
    assert_equal 2, as_business(@business) { @request_record.create_quote!(by: @owner) && Quote.where(service_request: @request_record).count }, "CLI-04: several quotes from the inbox"
    as_business(@business) { @request_record.update!(status: "archived") }
    assert_raises(ArgumentError) { as_business(@business) { @request_record.create_quote!(by: @tech, once: true) } }
  end

  test "without Send their own quotes, they mark the draft ready for review; the office hears, sees who drafted it, and sends it" do
    quote = quote_it
    get edit_admin_quote_path(quote)
    assert_select "button[form=ready-for-review-form]", /Ready for review/
    assert_select "p", /Mark it ready for review from the top of the page/
    get new_admin_quote_send_path(quote)
    assert_response :forbidden

    ready(lines_on(quote))
    assert_redirected_to edit_admin_quote_path(quote)
    follow_redirect!
    assert_select "#ready-for-review", /the office sends it/
    as_business(@business) do
      assert_equal [ @tech, "ready_for_review" ], [ quote.reload.ready_for_review_by, quote.events.last.kind ]
      notice = Notification.find_by!(user: @owner, kind: "quote_ready_for_review")
      assert_equal "Marcus Reyes's quote #{quote.number} for Maria Lopez is ready to check", notice.title
      assert_empty Notification.where(user: @tech, kind: "quote_ready_for_review"), "not the one who marked it"
    end

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get edit_admin_quote_path(quote)
    assert_select "#review-banner", /Marcus Reyes marked this ready for review/
    as_business(@business) { quote.update_columns(ready_for_review_at: nil) }
    get edit_admin_quote_path(quote)
    assert_select "#drafted-by", "Drafted by Marcus Reyes."
    as_business(@business) { quote.update_columns(ready_for_review_at: Time.current, ready_for_review_by_id: @tech.id) }
    post admin_quote_send_path(quote), params: { channel: "link" }
    get admin_quote_path(quote)
    assert_select "body", /Created by Marcus Reyes/
    assert_select "body", /Marked ready for review by Marcus Reyes/
    assert_select "body", /Link copied by John Doe/
  end

  test "with Send their own quotes, they send their own draft, which counts toward the plan, and not anyone else's" do
    as_business(@business) { @senior.update!(permissions: %w[field_work quote_requests send_own_quotes]) }
    quote = quote_it
    assert_match "Nothing is sent until you send it", flash[:notice]
    patch admin_quote_path(quote), params: builder_params(quote, lines: [ { key: "k1", name: "Weekly mowing", quantity: "1", unit_price: "45", taxable: "0" } ]), as: :turbo_stream
    get edit_admin_quote_path(quote)
    assert_select "a[href=?]", new_admin_quote_send_path(quote), /Send/
    assert_select "button[form=ready-for-review-form]", 0
    get new_admin_quote_send_path(quote)
    assert_response :success
    used = as_business(@business) { @business.reload.entitlements.used(:quotes_sent) }
    post admin_quote_send_path(quote), params: { channel: "link" }
    assert_redirected_to new_admin_quote_send_path(quote)
    follow_redirect!
    assert_response :success, "the link to copy, after sending their own"
    as_business(@business) do
      assert_equal "sent", quote.reload.status
      assert_equal @tech, quote.sends.sole.user
      assert_equal used + 1, Business.find(@business.id).entitlements.used(:quotes_sent)
    end
    get edit_admin_quote_path(quote)
    assert_response :not_found, "sent: no more editing"

    get new_admin_quote_send_path(@office_quote)
    assert_response :not_found

    as_business(@business) { quote.reload.revise!(by: @owner) }
    get new_admin_quote_send_path(quote)
    assert_response :not_found, "a revision the office started is the office's to send"
  end

  def lines_on(quote)
    patch admin_quote_path(quote), params: builder_params(quote, lines: [ { key: "k1", name: "Weekly mowing", quantity: "1", unit_price: "45", taxable: "0" } ]), as: :turbo_stream
    as_business(@business) { quote.reload }
  end

  def ready(quote) = post(ready_admin_quote_path(quote), params: { lock_version: as_business(@business) { quote.reload.lock_version } })

  test "ready for review: once (no second notice), with a line, from a current page; editing takes it back; sending, and revising, leave no stale banner" do
    quote = quote_it
    as_business(@business) { quote.line_items.delete_all }
    ready(quote)
    assert_equal "Add at least one line before marking it ready.", flash[:alert]
    lines_on(quote)
    post ready_admin_quote_path(quote), params: { lock_version: 0 }
    assert_match "changed since you last saw it", flash[:alert]
    ready(quote)
    ready(quote)
    assert_equal 1, as_business(@business) { Notification.where(kind: "quote_ready_for_review", user: @owner).count }
    assert_equal 1, as_business(@business) { quote.events.where(kind: "ready_for_review").count }

    patch admin_quote_path(quote), params: builder_params(quote, title: "Changed my mind",
                                                                 lines: [ { key: "k1", name: "Weekly mowing", quantity: "2", unit_price: "45", taxable: "0" } ]), as: :turbo_stream
    assert_select "turbo-stream[target=review-state] template button", /Ready for review/
    assert_not as_business(@business) { quote.reload.ready_for_review? }
    ready(quote)
    assert_equal 2, as_business(@business) { Notification.where(kind: "quote_ready_for_review", user: @owner).count }, "marked again after a change"

    as_business(@business) do
      quote.reload.mark_sent!(by: @owner, channel: "link")
      assert_nil quote.reload.ready_for_review_at
      quote.revise!(by: @owner)
      quote.update_columns(ready_for_review_at: Time.current) # as if left over
      assert_not quote.reload.ready_for_review?, "the office's revision isn't waiting for review"
    end
  end

  test "ready is only for those who don't send themselves, and only on their own draft" do
    quote = lines_on(quote_it)
    other = User.create!(email: "tia@example.com", password: "password123", first_name: "Tia", confirmed_at: Time.current)
    BusinessUser.create!(user: other, business: @business, role: "custom", role_id: @senior.id)
    sign_in other
    post switch_admin_business_path, params: { business: @business.uid }
    ready(quote)
    assert_response :not_found

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    ready(quote)
    assert_equal "You send this quote yourself.", flash[:alert]

    as_business(@business) { @senior.update!(permissions: %w[field_work quote_requests send_own_quotes]) }
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    ready(quote)
    assert_equal "You send this quote yourself.", flash[:alert]
    assert_nil as_business(@business) { quote.reload.ready_for_review_at }
  end

  test "sending their own: by email to the client's address on file only, within the plan, never without quoting too, nor across businesses" do
    as_business(@business) do
      @maria.contact_methods.create!(kind: "email", value: "maria@example.com")
      @senior.update!(permissions: %w[field_work quote_requests send_own_quotes])
    end
    quote = lines_on(quote_it)
    send_email = ->(to:, cc: "") { post admin_quote_send_path(quote), params: { quote_send: { to:, cc:, subject: "Your quote", message: "Hi" } } }
    send_email.(to: "someone@elsewhere.example")
    assert_response :unprocessable_content
    assert_select "body", /client's email on file/
    send_email.(to: "maria@example.com", cc: "boss@elsewhere.example")
    assert_response :unprocessable_content

    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil, "quotes_sent" => 0 } })
    send_email.(to: "maria@example.com")
    assert_equal "draft", as_business(@business) { quote.reload.status }, "the plan's limit holds for them too"

    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    send_email.(to: "Maria@Example.com")
    assert_redirected_to admin_root_path
    assert_equal [ "sent", "maria@example.com" ], as_business(@business) { [ quote.reload.status, quote.sends.sole.recipient.downcase ] }

    as_business(@business) { @senior.update!(permissions: %w[field_work send_own_quotes]) }
    get new_admin_quote_send_path(quote)
    assert_response :forbidden, "sending their own needs quoting their own too"

    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get new_admin_quote_send_path(quote) }
    assert_not_found_across_businesses { post admin_quote_send_path(quote), params: { channel: "link" } }
  end
end
