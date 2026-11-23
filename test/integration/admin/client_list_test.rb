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
    assert_permission_matrix(owner: true, admin: true, technician: false) { post search_admin_clients_path(format: :json), params: { q: "a" } }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post search_admin_clients_path, params: { q: "a" } }
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
      assert_select "time[datetime][title$=ago]", /\A\w{3} \d+, \d{4}\z/ # PLT-18: a date, how long ago on hover
    end
    assert_select "li#client-#{maria.uid}-row a[href=?]", admin_client_path(maria)
  end

  test "search, tag filter and sort, answered inside the results frame" do
    client("Maria Lopez", phone: "(555) 010-0100", tags: %w[commercial])
    client("Sam Okafor", phone: "555-010-0299")
    get admin_clients_path
    assert_select "form#client-filters[method=post][action=?][data-turbo-frame=client_results]", search_admin_clients_path

    post search_admin_clients_path, params: { q: "010-0299" }, headers: { "Turbo-Frame" => "client_results" }
    assert_select "turbo-frame#client_results tbody tr", 1
    assert_select "tbody", /Sam Okafor/
    assert_select "#app-sidebar", false, "the frame response has no layout"

    post search_admin_clients_path, params: { tag: "commercial" }
    assert_select "tbody tr", 1
    get admin_clients_path(tag: "commercial")
    assert_select "select#tag option[selected]", "commercial"

    post search_admin_clients_path, params: { sort: "recent" }
    assert_equal [ "Sam Okafor", "Maria Lopez" ], css_select("tbody tr td:first-child a").map(&:text)
    post search_admin_clients_path, params: { sort: "bogus" }
    assert_equal [ "Maria Lopez", "Sam Okafor" ], css_select("tbody tr td:first-child a").map(&:text)
  end

  test "the archived tab is a control of the filter form, rendered with the results" do
    old = client("Old Client")
    as_business(@business) { old.archive! }
    client("Current Client")
    post search_admin_clients_path, params: { q: "client" }
    assert_select "tbody tr", 1
    assert_select "input[type=radio][name=archived][form=client-filters][value='0'][checked]"
    post search_admin_clients_path, params: { q: "client", archived: "1" }
    assert_select "tbody", /Old Client/
    assert_select "input[type=radio][name=archived][value='1'][checked]"
    assert_select "button[form=client-filters][name=page]", 2
  end

  test "empty states guide the user" do
    get admin_clients_path
    assert_select "main", /Add your first client/
    client("Maria Lopez")
    post search_admin_clients_path, params: { q: "nobody" }
    assert_select "turbo-frame#client_results", /No clients match/
    assert_select "a[href=?]", admin_clients_path, "Clear search"
  end

  test "pages of fifty" do
    now = Time.current
    as_business(@business) { Client.insert_all!(Array.new(60) { |i| { business_id: @business.id, uid: SecureRandom.base58(12), display_name: "C#{i.to_s.rjust(2, "0")}",
                                              search_text: "c#{i}", created_at: now, updated_at: now, last_activity_at: now } }) }
    get admin_clients_path
    assert_select "tbody tr", 50
    assert_select "button[name=page][value='2']:not([disabled])", "Next"
    post search_admin_clients_path, params: { page: 2 }
    assert_select "tbody tr", 10
    assert_select "button[name=page][value='3'][disabled]"
  end

  test "the picker search returns active matches as JSON" do
    maria = client("Maria Lopez", phone: "(555) 010-0100")
    gone = client("Maria Gone", phone: "555-010-0101")
    as_business(@business) { gone.archive! }
    post search_admin_clients_path(format: :json), params: { q: "maria" }
    assert_equal [ maria.uid ], response.parsed_body["clients"].pluck("uid")
    assert_equal "(555) 010-0100", response.parsed_body["clients"].first["contact"]
  end

  test "another business's clients never appear" do
    client("Maria Theirs", business: businesses(:two))
    post search_admin_clients_path, params: { q: "maria" }
    assert_select "tbody tr", 0
    post search_admin_clients_path(format: :json), params: { q: "maria" }
    assert_empty response.parsed_body["clients"]
  end
end
