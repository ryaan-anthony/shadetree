require "test_helper"

# CAT-08: catalog prices and default taxes per location.
class Admin::LocationPricingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    @main = @business.primary_location
    as_business(@business) do
      @state = TaxRate.create!(name: "State", percent: "6.25", applies_by_default: true)
      @county = TaxRate.create!(name: "County", percent: "1", applies_by_default: false)
      @north = Location.create!(name: "North yard", tax_rate_ids: [ @county.id ])
      @mowing = CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45")
      @edging = CatalogItem.create!(name: "Edging", unit: "visit", unit_price: "20")
      LocationPrice.create!(location: @north, catalog_item: @mowing, unit_price: "55")
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "1 Elm St", billing: true } ])
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def picker(location: nil) = (get search_admin_catalog_items_path(format: :json, q: "", location:)) && response.parsed_body["items"].to_h { [ _1["name"], _1["unit_price"] ] }

  test "prices resolve per location, with the business price where there's no override" do
    as_business(@business) do
      assert_equal "55.00", @mowing.price_at(@north).to_s
      assert_equal "45.00", @mowing.price_at(@main).to_s
      assert_equal "20.00", @edging.price_at(@north).to_s
    end
    assert_equal({ "Edging" => "20.00", "Mowing" => "55.00" }, picker(location: @north.uid))
    assert_equal({ "Edging" => "20.00", "Mowing" => "45.00" }, picker)
    theirs = businesses(:two).primary_location
    assert_equal({ "Edging" => "20.00", "Mowing" => "45.00" }, picker(location: theirs.uid), "another business's location is ignored")
  end

  test "new documents take the location's default taxes; a request's quote takes its prices" do
    as_business(@business) do
      assert_equal [ "County" ], Quote.start(client: @maria, location: @north).tax_rate_list.map(&:name)
      assert_equal [ "State" ], Quote.start(client: @maria, location: @main).tax_rate_list.map(&:name)
      @north.update!(tax_rate_ids: nil)
      assert_equal [ "State" ], Quote.start(client: @maria, location: @north).tax_rate_list.map(&:name), "none of its own: the business's"
      request = ServiceRequest.create!(client: @maria, source: "phone", description: "Lawn", location: @north,
                                       services: [ { "catalog_item_id" => @mowing.id, "name" => "Mowing" } ])
      assert_equal [ 5_500 ], request.create_quote!(by: users(:one)).line_items.map(&:unit_price_cents)
    end
  end

  test "overrides are set on the catalog item, shown at a glance, and never change documents" do
    quote = as_business(@business) do
      Quote.start(client: @maria, location: @north).tap { _1.sync_line_items([ { "key" => "a", "catalog_item" => @mowing.uid, "name" => "Mowing", "quantity" => "1", "unit_price" => "55" } ]); _1.save! }
    end
    get admin_catalog_items_path
    assert_select "#item-#{@mowing.uid} .badge", "North yard: $55.00"
    get new_admin_catalog_item_path(duplicate_of: @mowing.uid)
    assert_select "input[name='catalog_item[location_price_inputs][#{@north.uid}]'][value='55.00']", 1, "a copy keeps its location prices"
    get edit_admin_catalog_item_path(@edging)
    assert_select "input[name='catalog_item[location_price_inputs][#{@north.uid}]'][placeholder='20.00']"

    patch admin_catalog_item_path(@mowing), params: { catalog_item: { name: "Mowing", location_price_inputs: { @north.uid => "60" } } }
    assert_equal 6_000, as_business(@business) { @mowing.price_at(@north).cents }
    assert_equal [ 5_500 ], as_business(@business) { quote.reload.line_items.map(&:unit_price_cents) }, "existing documents keep their prices"
    patch admin_catalog_item_path(@mowing), params: { catalog_item: { name: "Mowing", location_price_inputs: { @north.uid => "lots" } } }
    assert_response :unprocessable_content
    patch admin_catalog_item_path(@mowing), params: { catalog_item: { name: "Mowing", location_price_inputs: { @north.uid => "" } } }
    assert_equal 4_500, as_business(@business) { @mowing.price_at(@north).cents }, "cleared: the business price"
  end

  def draft_at(location, mowing_price: "45", invoice: false)
    as_business(@business) do
      (invoice ? Invoice : Quote).start(client: @maria, location:).tap do |doc|
        doc.sync_line_items([ { "key" => "a", "catalog_item" => @mowing.uid, "name" => "Mowing", "quantity" => "2", "unit_price" => mowing_price },
                              { "key" => "b", "catalog_item" => @edging.uid, "name" => "Edging", "quantity" => "1", "unit_price" => "20" },
                              { "key" => "c", "name" => "Haul away", "quantity" => "1", "unit_price" => "30" } ])
        doc.save!
      end
    end
  end

  test "moving a draft to another location offers its prices, listed, until accepted or kept" do
    quote = draft_at(@main)
    patch admin_quote_path(quote), params: { quote: { lock_version: quote.lock_version, location: @north.uid } }, as: :turbo_stream
    assert_match "Mowing $45.00 → $55.00", response.body
    assert_match "Taxes: State → County", response.body
    assert_no_match "Edging $20.00", response.body, "no override at either location: nothing to offer"

    get edit_admin_quote_path(quote)
    assert_select "#location_reprice .banner", /was priced for New York/, "still offered after a reload"
    assert_select "form#quote-builder form", 0, "no form inside the builder"
    assert_select "form#location-reprice-form input[name=lock_version]"

    patch reprice_admin_quote_path(quote), params: { lock_version: quote.reload.lock_version - 1 }
    assert_match "changed in another tab", flash[:alert]
    patch reprice_admin_quote_path(quote), params: { lock_version: quote.reload.lock_version }
    assert_redirected_to edit_admin_quote_path(quote)
    assert_equal "Prices and taxes now match North yard.", flash[:notice]
    as_business(@business) do
      quote.reload
      assert_equal [ 5_500, 2_000, 3_000 ], quote.current_line_items.map(&:unit_price_cents), "only catalog lines with an override change"
      assert_equal [ "County" ], quote.tax_rate_list.map(&:name)
      assert_equal 11_000 + 2_000 + 3_000, quote.subtotal_cents
      assert_not quote.repricing_offer?
      assert_equal "repriced", quote.events.last.kind
    end
  end

  test "hand-typed prices are left alone, and staff can keep theirs" do
    edited = draft_at(@main, mowing_price: "40")
    as_business(@business) do
      edited.update!(location: @north)
      assert_empty edited.location_price_changes, "Mowing was typed as $40: not offered"
    end

    quote = draft_at(@main)
    as_business(@business) { quote.update!(location: @north) }
    patch reprice_admin_quote_path(quote), params: { lock_version: quote.reload.lock_version, keep: "1" }
    as_business(@business) do
      quote.reload
      assert_equal [ 4_500, 2_000, 3_000 ], quote.current_line_items.map(&:unit_price_cents)
      assert_not quote.repricing_offer?, "kept: priced for North yard now"
    end
  end

  test "invoices are re-priced too, and a duplicate from an archived location is offered its new prices" do
    invoice = draft_at(@main, invoice: true)
    as_business(@business) { invoice.update!(location: @north) }
    patch reprice_admin_invoice_path(invoice), params: { lock_version: invoice.reload.lock_version }
    assert_equal [ 5_500, 2_000, 3_000 ], as_business(@business) { invoice.reload.current_line_items.map(&:unit_price_cents) }
    assert_equal "repriced", as_business(@business) { invoice.events.last.kind }

    quote = draft_at(@north, mowing_price: "55")
    as_business(@business) do
      @north.archive!
      copy = quote.reload.duplicate!
      assert_equal @main, copy.location
      assert_equal [ [ "Mowing", 4_500 ] ], copy.location_price_changes.map { |line, price| [ line.name, price.cents ] }
    end
  end

  test "only Owners and Admins re-price or set location prices and taxes" do
    quote, invoice = draft_at(@main), draft_at(@main, invoice: true)
    sign_out :user
    assert_permission_matrix(owner: true, admin: true) { patch reprice_admin_quote_path(quote), params: { lock_version: 0 } }
    as_technician { patch reprice_admin_quote_path(quote), params: { lock_version: 0 } }
    assert_response :not_found, "QTE-07: Technicians reach only their own drafts from requests"
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch reprice_admin_invoice_path(invoice), params: { lock_version: 0 } }
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch admin_catalog_item_path(@mowing), params: { catalog_item: { name: "Mowing", location_price_inputs: { @north.uid => "70" } } } }
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch admin_location_path(@north), params: { location: { name: "North yard", own_tax_rates: "0" } } }
  end

  test "with one location none of it appears, and other businesses' records aren't found" do
    get edit_admin_location_path(@north)
    assert_select "input[name='location[tax_rate_ids][]']", 2
    patch admin_location_path(@north), params: { location: { name: "North yard", own_tax_rates: "1", tax_rate_ids: [ @state.uid, "nope" ] } }
    assert_equal [ @state.id ], @north.reload.tax_rate_ids
    patch admin_location_path(@north), params: { location: { name: "North yard", own_tax_rates: "0", tax_rate_ids: [ @state.uid ] } }
    assert_nil @north.reload.tax_rate_ids, "back to the business's defaults"
    theirs = as_business(businesses(:two)) { Quote.start(client: Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])) }
    assert_not_found_across_businesses { patch reprice_admin_quote_path(theirs) }
    their_invoice = as_business(businesses(:two)) { Invoice.start(client: theirs.client) }
    assert_not_found_across_businesses { patch reprice_admin_invoice_path(their_invoice) }
    their_location = businesses(:two).primary_location
    patch admin_catalog_item_path(@mowing), params: { catalog_item: { name: "Mowing", location_price_inputs: { their_location.uid => "99" } } }
    assert_equal 0, Tenancy.across_businesses(reason: "test") { LocationPrice.where(location_id: their_location.id).count }, "another business's location is ignored"

    as_business(@business) { @north.destroy! }
    get edit_admin_catalog_item_path(@mowing)
    assert_select "input[name^='catalog_item[location_price_inputs]']", 0
    get admin_catalog_items_path
    assert_select "#item-#{@mowing.uid} .badge", 0
  end
end
