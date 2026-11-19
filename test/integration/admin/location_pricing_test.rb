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
    assert_select "#item-#{@mowing.uid} .badge", "North yard $55.00"
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

  test "moving a draft to another location offers to re-price it" do
    quote = as_business(@business) do
      Quote.start(client: @maria, location: @main).tap do |q|
        q.sync_line_items([ { "key" => "a", "catalog_item" => @mowing.uid, "name" => "Mowing", "quantity" => "2", "unit_price" => "45" },
                            { "key" => "b", "name" => "Haul away", "quantity" => "1", "unit_price" => "30" } ])
        q.save!
      end
    end
    patch admin_quote_path(quote), params: { quote: { lock_version: quote.lock_version, location: @north.uid } }, as: :turbo_stream
    assert_match "North yard has 1 different price and different default taxes", response.body
    patch reprice_admin_quote_path(quote)
    assert_redirected_to edit_admin_quote_path(quote)
    as_business(@business) do
      quote.reload
      assert_equal [ 5_500, 3_000 ], quote.current_line_items.map(&:unit_price_cents), "only catalog lines change"
      assert_equal [ "County" ], quote.tax_rate_list.map(&:name)
      assert_equal 11_000 + 3_000, quote.subtotal_cents
    end
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

    as_business(@business) { @north.destroy! }
    get edit_admin_catalog_item_path(@mowing)
    assert_select "input[name^='catalog_item[location_price_inputs]']", 0
    get admin_catalog_items_path
    assert_select "#item-#{@mowing.uid} .badge", 0
  end
end
