require "test_helper"

# CLI-02: the client list, search as you type, and the picker's search.
class Admin::ClientListTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def client(name, phone: "555-010-0100", tags: [], business: @business, **attributes)
    as_business(business) do
      Client.create!(display_name: name, tags:, contact_methods_attributes: [ { kind: "phone", value: phone } ], **attributes)
    end
  end

  test "technicians can't see the list or search" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_clients_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get search_admin_clients_path(format: :json, q: "a") }
  end

  test "the list shows contact, property, tags and last activity in a table and a mobile list" do
    maria = client("Maria Lopez", tags: %w[commercial], company_name: "Lopez Rentals",
                   properties_attributes: [ { address_line1: "12 Elm St", city: "Austin" } ])
    get admin_clients_path
    assert_select "table.data-table tr#client-#{maria.uid}" do
      assert_select "a[href=?]", admin_client_path(maria), "Maria Lopez"
      assert_select "td", /Lopez Rentals/
      assert_select "a[href='tel:5550100100']", "555-010-0100"
      assert_select "td", "12 Elm St, Austin"
      assert_select ".badge", "commercial"
      assert_select "time[datetime]", /ago/
    end
    assert_select "li#client-#{maria.uid}-row a[href=?]", admin_client_path(maria)
  end

  test "search, tag filter and sort, answered inside the results frame" do
    client("Maria Lopez", phone: "(555) 010-0100", tags: %w[commercial])
    client("Sam Okafor", phone: "555-010-0299")
    get admin_clients_path(q: "010-0299"), headers: { "Turbo-Frame" => "client_results" }
    assert_select "turbo-frame#client_results tbody tr", 1
    assert_select "tbody", /Sam Okafor/

    get admin_clients_path(tag: "commercial")
    assert_select "tbody tr", 1
    assert_select "select#tag option[selected]", "commercial"

    get admin_clients_path(sort: "recent")
    assert_equal [ "Sam Okafor", "Maria Lopez" ], css_select("tbody tr td:first-child a").map(&:text)
    get admin_clients_path(sort: "bogus")
    assert_equal [ "Maria Lopez", "Sam Okafor" ], css_select("tbody tr td:first-child a").map(&:text)
  end

  test "archived clients have their own tab, and filters carry across tabs" do
    old = client("Old Client")
    as_business(@business) { old.archive! }
    client("Current Client")
    get admin_clients_path(q: "client")
    assert_select "tbody tr", 1
    assert_select "nav.tabs a[href=?]", admin_clients_path(q: "client", archived: 1)
    get admin_clients_path(archived: 1, q: "client")
    assert_select "tbody", /Old Client/
  end

  test "empty states guide the user" do
    get admin_clients_path
    assert_select "main", /Add your first client/
    client("Maria Lopez")
    get admin_clients_path(q: "nobody")
    assert_select "main", /No clients match/
    assert_select "a[href=?]", admin_clients_path, "Clear search"
  end

  test "pages of fifty" do
    now = Time.current
    as_business(@business) { Client.insert_all!(Array.new(60) { |i| { business_id: @business.id, uid: SecureRandom.base58(12), display_name: "C#{i.to_s.rjust(2, "0")}",
                                              search_text: "c#{i}", created_at: now, updated_at: now, last_activity_at: now } }) }
    get admin_clients_path
    assert_select "tbody tr", 50
    get admin_clients_path(page: 2)
    assert_select "tbody tr", 10
  end

  test "the picker search returns active matches as JSON" do
    maria = client("Maria Lopez", phone: "(555) 010-0100")
    gone = client("Maria Gone", phone: "555-010-0101")
    as_business(@business) { gone.archive! }
    get search_admin_clients_path(format: :json, q: "maria")
    assert_equal [ maria.uid ], response.parsed_body["clients"].pluck("uid")
    assert_equal "(555) 010-0100", response.parsed_body["clients"].first["contact"]
  end

  test "another business's clients never appear" do
    client("Maria Theirs", business: businesses(:two))
    get admin_clients_path(q: "maria")
    assert_select "tbody tr", 0
    get search_admin_clients_path(format: :json, q: "maria")
    assert_empty response.parsed_body["clients"]
  end
end
