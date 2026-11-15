require "test_helper"

# CAT-05: adding starter services from the catalog page.
class Admin::CatalogPresetsTest < ActionDispatch::IntegrationTest
  setup do
    IndustryPreset.sync!
    @business = businesses(:one)
    @business.update_column(:industry, "cleaning")
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "only owners and admins add starter services" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_catalog_presets_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      post admin_catalog_presets_path, params: { industry: "cleaning", names: [ "Deep clean" ] }
    end
  end

  test "the empty catalog and the dashboard point to starter services" do
    get admin_catalog_items_path
    assert_select "a[href=?]", admin_catalog_presets_path, /Add starter services/
    get admin_root_path
    assert_select "a[href=?]", admin_catalog_presets_path, "Add services"
  end

  test "preview the business's industry, pick some, add them" do
    as_business(@business) { CatalogItem.create!(name: "Deep clean") }
    get admin_catalog_presets_path
    assert_select "select#industry option[selected][value=cleaning]"
    assert_select "input[type=checkbox][name='names[]'][value='Standard clean'][checked]"
    assert_select "input[type=checkbox][value='Deep clean']", false
    assert_select "li", /Deep clean.*In your catalog/m

    post admin_catalog_presets_path, params: { industry: "cleaning", names: [ "Standard clean", "Inside fridge" ] }
    assert_redirected_to admin_catalog_items_path
    assert_equal "Added 2 services to your catalog. Set your prices next.", flash[:notice]
    assert_equal [ "Deep clean", "Inside fridge", "Standard clean" ], as_business(@business) { CatalogItem.order(:name).pluck(:name) }

    post admin_catalog_presets_path, params: { industry: "cleaning", names: [ "Standard clean" ] }
    assert_equal "Nothing new to add: those services are already in your catalog.", flash[:notice]
  end

  test "another industry's preset can be previewed" do
    get admin_catalog_presets_path(industry: "pest")
    assert_select "input[value='Rodent control']"
    get admin_catalog_presets_path(industry: "nonsense")
    assert_select "select#industry option[selected][value=cleaning]"
  end

  test "a business without an industry is asked to choose one" do
    @business.update_column(:industry, nil)
    get admin_catalog_presets_path
    assert_select "select#industry option[value='']", "Choose an industry"
    assert_select "main", /Your business has no industry set/
    assert_select "input[type=submit][value='Show services']"
  end

  test "submitting with nothing ticked asks for a pick" do
    post admin_catalog_presets_path, params: { industry: "cleaning" }
    assert_redirected_to admin_catalog_presets_path(industry: "cleaning")
    assert_equal "Pick at least one service to add.", flash[:alert]
    assert_empty as_business(@business) { CatalogItem.all.to_a }
  end

  test "an unknown industry on submit is not found" do
    post admin_catalog_presets_path, params: { industry: "nonsense", names: [ "x" ] }
    assert_response :not_found
  end
end
