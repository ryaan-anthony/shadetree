require "test_helper"

# QTE-08: in Services & prices, the services technicians may send without review, and the
# business's optional cap on such quotes' totals.
class Admin::SendWithoutReviewSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    @gutters = as_business(@business) { CatalogItem.create!(name: "Gutter clean", unit: "visit", unit_price: "150") }
  end

  test "the switch is off by default, set on the service, and marked in the list" do
    assert_not @gutters.send_without_review
    get edit_admin_catalog_item_path(@gutters)
    assert_select "input[type=checkbox][name='catalog_item[send_without_review]']:not([checked])"
    assert_select "label", /Technicians can send without review/

    get admin_catalog_items_path
    assert_select "#review-cap", 0, "no cap to set until a service has the switch on"
    assert_select "#item-#{@gutters.uid} .badge", text: "Sent without review", count: 0

    patch admin_catalog_item_path(@gutters), params: { catalog_item: { send_without_review: "1" } }
    assert as_business(@business) { @gutters.reload.send_without_review }
    get admin_catalog_items_path
    assert_select "#item-#{@gutters.uid} .badge", text: "Sent without review"
    assert_select "#review-cap", /1 service technicians can send without review/
    assert_select "#review-cap input[name=without_review_cap][placeholder='No cap']"
  end

  test "the cap: an amount, tax included; blank for none; a negative or unreadable one is refused" do
    as_business(@business) { @gutters.update!(send_without_review: true) }
    patch review_cap_admin_catalog_items_path, params: { without_review_cap: "500" }
    assert_redirected_to admin_catalog_items_path
    assert_equal "Quotes sent without review can total up to $500.00, tax included.", flash[:notice]
    assert_equal 50_000, @business.reload.without_review_cap_cents
    get admin_catalog_items_path
    assert_select "#review-cap input[name=without_review_cap][value='500.00']"

    patch review_cap_admin_catalog_items_path, params: { without_review_cap: "-5" }
    assert_match "can't be negative", flash[:alert]
    patch review_cap_admin_catalog_items_path, params: { without_review_cap: "lots" }
    assert_match "is not a valid amount", flash[:alert]
    assert_equal 50_000, @business.reload.without_review_cap_cents

    patch review_cap_admin_catalog_items_path, params: { without_review_cap: " " }
    assert_equal "No cap on quotes sent without review.", flash[:notice]
    assert_nil @business.reload.without_review_cap_cents
  end

  test "only people who manage services set them" do
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      patch review_cap_admin_catalog_items_path, params: { without_review_cap: "1" }
    end
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      patch admin_catalog_item_path(@gutters), params: { catalog_item: { send_without_review: "1" } }
    end
  end

  test "a business's cap and switches are its own" do
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { patch admin_catalog_item_path(@gutters), params: { catalog_item: { send_without_review: "1" } } }
    patch review_cap_admin_catalog_items_path, params: { without_review_cap: "9" }
    assert_nil @business.reload.without_review_cap_cents
  end

  test "a quote line keeps the price its service had when it was added, and picks up the new one when added again" do
    as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
      quote = Quote.start(client:)
      quote.sync_line_items([ { "key" => "a", "catalog_item" => @gutters.uid, "name" => "Gutter clean", "unit_price" => "150", "quantity" => "1" },
                              { "key" => "b", "name" => "Extra", "unit_price" => "10", "quantity" => "1" } ])
      quote.save!
      assert_equal [ 15_000, nil ], quote.line_items.map(&:catalog_price_cents)

      @gutters.update!(unit_price: "175")
      quote.sync_line_items([ { "key" => "a", "catalog_item" => @gutters.uid, "quantity" => "2" } ])
      quote.save!
      assert_equal 15_000, quote.line_items.reload.sole.catalog_price_cents, "an edit isn't re-adding it"

      quote.sync_line_items([ { "key" => "c", "catalog_item" => @gutters.uid, "name" => "Gutter clean", "unit_price" => "175", "quantity" => "1" } ])
      quote.save!
      assert_equal [ 17_500 ], quote.line_items.reload.map(&:catalog_price_cents)
    end
  end
end
