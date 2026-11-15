require "test_helper"

# QTE-01: the quote builder.
class Admin::QuotesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(quote_expiry_days: 30, quote_terms: "Due on completion.")
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    @maria = client("Maria Lopez")
  end

  def client(name, exempt: false, business: @business)
    as_business(business) do
      Client.create!(display_name: name, tax_exempt: exempt, contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                     properties_attributes: [ { address_line1: "#{name.length} Elm St", billing: true } ])
    end
  end

  def draft(for_client = @maria) = as_business(@business) { Quote.start(client: for_client) }

  # Reads a quote fresh, inside the business (reads outside one fail closed).
  def fresh(quote, &) = as_business(@business) { yield quote.reload }

  def builder_params(quote, lines: [], **fields)
    { quote: { lock_version: quote.lock_version, lines_present: "1", client: as_business(@business) { quote.client.uid },
               lines: lines.each_with_index.to_h { |line, index| [ index.to_s, line ] }, **fields } }
  end

  test "technicians can't create or view quotes" do
    quote = draft
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_quotes_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_quote_path(quote) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_quotes_path, params: { quote: { client: @maria.uid } } }
  end

  test "starting a quote from the picker or from a client page" do
    get new_admin_quote_path
    assert_select "input[type=hidden][name='quote[client]']"
    post admin_quotes_path, params: { quote: { client: @maria.uid } }
    quote = as_business(@business) { Quote.last }
    assert_redirected_to edit_admin_quote_path(quote)
    assert_equal [ "Q-0001", @maria ], fresh(quote) { [ _1.number, _1.client ] }

    assert_no_difference(-> { as_business(@business) { Quote.count } }, "a GET (or a hover prefetch) never creates a draft") do
      get new_admin_quote_path(client: @maria.uid)
    end
    assert_select "input[type=hidden][name='quote[client]'][value=?]", @maria.uid

    get admin_client_path(@maria)
    assert_select "form[action=?][method=post] input[name='quote[client]'][value=?]", admin_quotes_path, @maria.uid

    post admin_quotes_path, params: { quote: { client: "" } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Choose a client/
  end

  test "the builder shows the draft with its defaults" do
    quote = draft
    get edit_admin_quote_path(quote)
    assert_select "h1", /Quote #{quote.number}/
    assert_select "form#quote-builder[data-controller=quote-builder]"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "#quote_terms", "Due on completion."
    assert_select "#quote_expires_on[value=?]", (Date.current + 30).iso8601
    assert_select "select#quote_property option[selected]", /Elm St/
    assert_select "template[data-quote-builder-target=template] input[name='quote[lines][NEW_INDEX][name]']"
    assert_select "#quote_totals", /Total.*\$0\.00/m
  end

  test "autosave saves the whole draft and answers with fresh totals" do
    as_business(@business) { TaxRate.create!(name: "State", percent: "6.25") }
    quote = draft
    patch admin_quote_path(quote), params: builder_params(quote, title: "Spring cleanup", tax_rates: [ "", "State|6.25" ],
      lines: [ { key: "k1", name: "Leaf cleanup", quantity: "1", unit_price: "180", taxable: "1" },
               { key: "k2", name: "Mulch", quantity: "2", unit_price: "40", taxable: "0" } ]), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target=quote_totals]" do
      assert_select "template", /State \(6\.25%\).*\$11\.25.*Total.*\$271\.25/m
    end
    assert_select "turbo-stream[action=update][target=line-total-k2] template", "$80.00"
    assert_select "turbo-stream[target=quote_lock_version] template input[value='1']"
    assert_equal "1", response.headers["X-Lock-Version"]

    assert_equal [ "Spring cleanup", 27_125, %w[Leaf\ cleanup Mulch] ], fresh(quote) { [ _1.title, _1.total_cents, _1.line_items.map(&:name) ] }
    quote = fresh(quote) { _1 }

    patch admin_quote_path(quote), params: builder_params(quote, lines: [ { key: "k2", name: "Mulch", quantity: "3", unit_price: "40", taxable: "0" } ]), as: :turbo_stream
    assert_equal [ [ "Mulch", BigDecimal("3") ] ], fresh(quote) { |q| q.line_items.map { [ _1.name, _1.quantity ] } }
  end

  test "a save from a stale tab is refused, not merged" do
    quote = draft
    stale = quote.lock_version
    patch admin_quote_path(quote), params: builder_params(quote, title: "From tab one"), as: :turbo_stream
    patch admin_quote_path(quote), params: builder_params(quote, title: "From tab two").deep_merge(quote: { lock_version: stale }), as: :turbo_stream
    assert_response :conflict
    assert_select "turbo-stream[target=builder_banner] template", /changed in another tab/
    assert_equal "From tab one", fresh(quote, &:title)
  end

  test "a stale tab can't overwrite line-only edits" do
    quote = draft
    lines = [ { key: "a", name: "Mow", quantity: "1", unit_price: "45" }, { key: "b", name: "Edge", quantity: "1", unit_price: "15" } ]
    patch admin_quote_path(quote), params: builder_params(quote, lines:), as: :turbo_stream
    stale = response.headers["X-Lock-Version"]

    tab_a = builder_params(quote, lines: [ lines[1].merge(name: "Edging (tab A)"), lines[0] ]).deep_merge(quote: { lock_version: stale })
    patch admin_quote_path(quote), params: tab_a, as: :turbo_stream
    assert_response :success
    assert_operator response.headers["X-Lock-Version"].to_i, :>, stale.to_i

    tab_b = builder_params(quote, lines: [ lines[0].merge(name: "Mow (tab B)"), lines[1] ]).deep_merge(quote: { lock_version: stale })
    patch admin_quote_path(quote), params: tab_b, as: :turbo_stream
    assert_response :conflict
    assert_equal [ "Edging (tab A)", "Mow" ], fresh(quote) { _1.line_items.map(&:name) }
  end

  test "invalid lines are explained and nothing is half-saved" do
    quote = draft
    patch admin_quote_path(quote), params: builder_params(quote, lines: [ { key: "k1", name: "Mowing", quantity: "1", unit_price: "lots" } ]), as: :turbo_stream
    assert_response :unprocessable_content
    assert_select "turbo-stream[target=builder_errors] template", /Mowing: Unit price is not a valid amount/
    assert_empty fresh(quote) { _1.line_items.to_a }
  end

  test "changing the client resets the property and the taxes when exemption differs" do
    as_business(@business) { TaxRate.create!(name: "State", percent: "6.25") }
    quote = draft
    church = client("Grace Church", exempt: true)
    # The form always sends the ticked rates; for the old client they were State.
    patch admin_quote_path(quote), params: builder_params(quote, property: fresh(quote) { _1.property.uid }, tax_rates: [ "", "State|6.25" ],
                                                         lines: [ { key: "k1", name: "Hedges", quantity: "1", unit_price: "100" } ])
                                                         .deep_merge(quote: { client: church.uid }), as: :turbo_stream
    assert_equal [ church, church.billing_property, [], 10_000 ], fresh(quote) { [ _1.client, _1.property, _1.tax_rates, _1.total_cents ] }
    assert_select "turbo-stream[action=replace][target=quote_tax_rates] template", /client is tax exempt/
    assert_select "turbo-stream[target=quote_tax_rates] template input[type=checkbox][checked]", false
    assert_select "turbo-stream[target=quote_property] template option[selected]", /Elm St/
  end

  test "quote discount, the explicit save button and the property options" do
    quote = draft
    patch admin_quote_path(quote), params: builder_params(quote, discount_kind: "percent", discount_value: "10",
                                                         lines: [ { key: "k1", name: "Mowing", quantity: "2", unit_price: "50" } ])
    assert_redirected_to edit_admin_quote_path(quote)
    assert_equal 9_000, fresh(quote, &:total_cents)

    get property_options_admin_quotes_path(client: @maria.uid)
    assert_select "turbo-frame#quote_property select option", 2
  end

  test "attachments: photos and PDFs, removable" do
    quote = draft
    patch admin_quote_path(quote), params: builder_params(quote, attachments: [ fixture_file_upload("logo.png", "image/png") ])
    assert_redirected_to edit_admin_quote_path(quote)
    file = fresh(quote) { _1.attachments.first }
    assert_equal "logo.png", file.filename.to_s
    follow_redirect!
    assert_select "#attachment-#{file.id}", /logo\.png/

    perform_enqueued_jobs { delete admin_quote_attachment_path(quote, file) }
    assert_not fresh(quote) { _1.attachments.attached? }
  end

  test "preview as client shows what the client will see, without internal notes" do
    quote = draft
    patch admin_quote_path(quote), params: builder_params(quote, message: "Thanks!", internal_notes: "Gate code 1234",
                                                         lines: [ { key: "k1", name: "Mowing", quantity: "1", unit_price: "45" } ])
    get preview_admin_quote_path(quote)
    assert_select ".client-card", /Mowing.*\$45\.00.*Total/m
    assert_select "body", text: /Gate code 1234/, count: 0
    assert_select "body", /Thanks!/
  end

  test "deleting a draft" do
    quote = draft
    delete admin_quote_path(quote)
    assert_redirected_to admin_quotes_path
    assert_nil as_business(@business) { Quote.find_by(id: quote.id) }
  end

  test "another business's quotes are not reachable" do
    theirs = as_business(businesses(:two)) { Quote.start(client: client("Theirs", business: businesses(:two))) }
    assert_not_found_across_businesses { get edit_admin_quote_path(theirs) }
    assert_not_found_across_businesses { patch admin_quote_path(theirs), params: { quote: { title: "x" } } }
    assert_not_found_across_businesses { delete admin_quote_path(theirs) }
    assert_not_found_across_businesses { get preview_admin_quote_path(theirs) }
    post admin_quotes_path, params: { quote: { client: theirs.client.uid } }
    assert_response :unprocessable_content
  end
end
