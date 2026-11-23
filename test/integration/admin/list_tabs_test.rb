require "test_helper"

# PLT-19: one style of tabs on every list, zero-count status tabs hidden (except "All" and the
# current one, owner 2026-11-22), and search as you type with no Search button.
class Admin::ListTabsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def tab_labels = css_select("nav.tabs .tab, fieldset.tabs .tab").map { _1.text.squish.sub(/\s*\d+\z/, "") }

  def make_client(name)
    as_business(@business) { Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: "5550100#{name.length}0" } ]) }
  end

  def make_quote(client)
    as_business(@business) do
      Quote.start(client:, created_by: users(:one)).tap do |quote|
        quote.sync_line_items([ { "key" => "a", "name" => "Hedges", "quantity" => "1", "unit_price" => "80", "taxable" => "0" } ])
        quote.save!
      end
    end
  end

  test "quote tabs at 0 are hidden, except All and the current one" do
    get admin_quotes_path
    assert_equal [ "All" ], tab_labels, "no quotes: only All"

    make_quote(make_client("Maria Lopez"))
    get admin_quotes_path
    assert_equal %w[All Drafts], tab_labels
    assert_select "nav.tabs button[value=draft] .tab-count", "1"

    get admin_quotes_path(filter: "archived")
    assert_equal %w[All Drafts Archived], tab_labels, "the current tab shows at 0"
    assert_select "nav.tabs button[value=archived][aria-pressed=true] .tab-count", "0"
  end

  test "job and invoice tabs follow the same rule" do
    get admin_jobs_path
    assert_equal [ "Not finished", "All" ], tab_labels # Not finished is the current tab
    get admin_invoices_path
    assert_equal [ "All" ], tab_labels
  end

  test "request tabs hide empty statuses except the current one" do
    client = make_client("Maria Lopez")
    as_business(@business) { ServiceRequest.create!(client:, source: "phone", description: "Fence", created_by: users(:one)) }
    get admin_service_requests_path(status: "quoted")
    assert_equal %w[New Quoted], tab_labels
    assert_select "nav.tabs a[aria-current=page]", /Quoted\s*0/
  end

  test "services: tabs on the left in the results, Archived once something is, and search as you type" do
    get admin_catalog_items_path
    assert_equal [ "Active" ], tab_labels
    assert_select "form#service-filters[method=get][data-controller=search-form][data-turbo-frame=service_results]" do
      assert_select "input[type=search][data-action*='search-form#queue']"
      assert_select "button, input[type=submit]", 0, "no Search button: Enter submits the GET form"
    end
    assert_select "turbo-frame#service_results[target=_top] nav.tabs a.tab[aria-current=page]", "Active"

    as_business(@business) { CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45").archive! }
    get admin_catalog_items_path(q: "mow")
    assert_equal %w[Active Archived], tab_labels
    assert_select "nav.tabs a.tab[href=?]", admin_catalog_items_path(archived: 1, q: "mow") do
      assert_select ".tab-count", "1"
    end
  end

  test "clients: the Archived tab shows once a client is archived" do
    maria = make_client("Maria Lopez")
    get admin_clients_path
    assert_equal [ "Active" ], tab_labels
    assert_select "fieldset.tabs input[type=radio][name=archived][form=client-filters][checked]", 1

    as_business(@business) { maria.archive! }
    get admin_clients_path
    assert_equal %w[Active Archived], tab_labels
    get admin_clients_path(archived: "1")
    assert_select "fieldset.tabs input[value='1'][checked]"
  end
end
