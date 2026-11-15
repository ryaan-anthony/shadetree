require "test_helper"

# CAT-03: the service catalog pages and the picker's search.
class Admin::CatalogTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
  end

  def as_member(user, business = @business)
    sign_in user
    post switch_admin_business_path, params: { business: business.uid }
  end

  def create_item(name, business: @business, **attributes)
    as_business(business) { CatalogItem.create!(name:, unit_price: "45", **attributes) }
  end

  test "managing the catalog needs business_settings" do
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_catalog_items_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      post admin_catalog_items_path, params: { catalog_item: { name: "Trip fee" } }
    end
  end

  test "the picker search is open to office roles" do
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      get search_admin_catalog_items_path(format: :json)
    end
  end

  test "an empty catalog invites the first item" do
    as_member(@owner)
    get admin_catalog_items_path
    assert_select "main", /Your catalog is empty/
  end

  test "adding an item with a new category" do
    as_member(@owner)
    post admin_catalog_items_path, params: { catalog_item: {
      name: "Weekly mow", unit_price: "45.50", unit: "visit", taxable: "1", duration_minutes: "40",
      new_category_name: "Lawn care"
    } }
    item = as_business(@business) { CatalogItem.find_by!(name: "Weekly mow") }
    assert_redirected_to admin_catalog_items_path(anchor: "item-#{item.uid}")
    assert_equal 4550, item.unit_price_cents
    assert_equal "Lawn care", as_business(@business) { item.category.name }

    follow_redirect!
    assert_select "section", /Lawn care.*Weekly mow.*\$45\.50.*visit/m
  end

  test "an existing category is reused when typed with different case" do
    lawn = as_business(@business) { CatalogCategory.create!(name: "Lawn care") }
    as_member(@owner)
    post admin_catalog_items_path, params: { catalog_item: { name: "Edging", new_category_name: "lawn CARE" } }
    assert_equal lawn, as_business(@business) { CatalogItem.find_by!(name: "Edging").category }
  end

  test "invalid input re-renders the form with errors" do
    as_member(@owner)
    post admin_catalog_items_path, params: { catalog_item: { name: "", unit_price: "lots", unit: "custom" } }
    assert_response :unprocessable_content
    assert_select ".banner-danger", /to fix/
    assert_select "input[name='catalog_item[unit_price]'][value=lots]"
  end

  test "a negative price and a new category survive a failed save" do
    as_member(@owner)
    post admin_catalog_items_path, params: { catalog_item: { name: "", unit_price: "-5", new_category_name: "Lawn care" } }
    assert_response :unprocessable_content
    assert_select "input#catalog_item_unit_price[aria-invalid=true]"
    assert_select ".error-text", /can't be negative/
    assert_select "input[name='catalog_item[new_category_name]'][value='Lawn care']"
  end

  test "editing, duplicating, archiving and restoring" do
    item = create_item("Weekly mow")
    as_member(@owner)

    patch admin_catalog_item_path(item), params: { catalog_item: { unit_price: "50" } }
    assert_equal 5000, item.reload.unit_price_cents

    get admin_catalog_items_path
    assert_select "a[href=?]", new_admin_catalog_item_path(duplicate_of: item.uid), /Duplicate/
    get new_admin_catalog_item_path(duplicate_of: item.uid)
    assert_select "input[name='catalog_item[name]'][value='Weekly mow (copy)']"

    patch archive_admin_catalog_item_path(item)
    assert item.reload.archived_at
    get admin_catalog_items_path
    assert_select "#item-#{item.uid}", false
    get admin_catalog_items_path(archived: 1)
    assert_select "#item-#{item.uid}", /Weekly mow/

    patch restore_admin_catalog_item_path(item)
    assert_nil item.reload.archived_at
  end

  test "moving reorders within a category" do
    a = create_item("A")
    b = create_item("B")
    as_member(@owner)
    patch move_admin_catalog_item_path(b, direction: -1)
    assert_equal %w[B A], as_business(@business) { CatalogItem.ordered.map(&:name) }
  end

  test "the index filters by search" do
    create_item("Hedge trim")
    create_item("Mulch")
    as_member(@owner)
    get admin_catalog_items_path(q: "hedge")
    assert_select "li[id^=item-]", 1
    assert_select "li[id^=item-]", /Hedge trim/
  end

  test "search JSON returns active matches and recents in order" do
    mow = create_item("Weekly mow", description: "Front and back")
    trim = create_item("Hedge trim")
    gone = create_item("Old service")
    as_business(@business) { gone.archive! }
    as_member(@owner)

    get search_admin_catalog_items_path(format: :json, q: "mow")
    assert_equal [ { "uid" => mow.uid, "name" => "Weekly mow", "description" => "Front and back", "unit" => "each",
                     "taxable" => true, "category" => nil, "price" => "$45.00", "unit_price" => "45.00", "unit_price_cents" => 4500 } ],
                 response.parsed_body["items"]

    get search_admin_catalog_items_path(format: :json, uids: [ trim.uid, gone.uid, mow.uid ].join(","))
    assert_equal [ trim.uid, mow.uid ], response.parsed_body["items"].pluck("uid")
  end

  test "another business's items are not reachable" do
    theirs = create_item("Their item", business: businesses(:two))
    as_member(@owner)
    get edit_admin_catalog_item_path(theirs)
    assert_response :not_found
    get search_admin_catalog_items_path(format: :json, q: "their")
    assert_empty response.parsed_body["items"]
  end

  test "the sidebar links to the catalog for settings roles only" do
    as_member(@owner)
    get admin_root_path
    assert_select "nav a[href='#{admin_catalog_items_path}']", "Catalog"
  end
end
