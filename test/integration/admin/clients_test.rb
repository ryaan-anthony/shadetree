require "test_helper"

# CLI-01: client pages, inline creation and duplicate suggestions.
class Admin::ClientsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
  end

  def as_member(user, business = @business)
    sign_in user
    post switch_admin_business_path, params: { business: business.uid }
  end

  def create_client(name = "Maria Lopez", business: @business, phone: "555-010-0100", **attributes)
    as_business(business) do
      Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: phone } ], **attributes)
    end
  end

  def client_params(**overrides)
    { display_name: "Maria Lopez",
      contact_methods_attributes: { "0" => { kind: "email", value: "maria@example.com" }, "1" => { kind: "phone", value: "(555) 010-0100", label: "Mobile" } },
      properties_attributes: { "0" => { address_line1: "1 Main St", city: "Austin", region: "TX", postal_code: "78701", country: "US",
                                        access_notes: "Gate code 1234", billing: "1" } },
      tag_list: "Weekly" }.merge(overrides)
  end

  test "client pages need the office permission" do
    client = create_client
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_clients_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_client_path(client) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_client_path(inline: 1) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post matches_admin_clients_path, params: { phone: [ "5550100100" ] } }
  end

  test "the empty list invites the first client" do
    as_member(@owner)
    get admin_clients_path
    assert_select "main", /Add your first client/
  end

  test "creating a client with contacts and a property" do
    as_member(@owner)
    get new_admin_client_path
    assert_select "input[name='client[contact_methods_attributes][0][value]'][type=email]"
    assert_select "template[data-kind=property]"

    post admin_clients_path, params: { client: client_params }
    client = as_business(@business) { Client.find_by!(display_name: "Maria Lopez") }
    assert_redirected_to admin_client_path(client)
    follow_redirect!
    assert_select "a[href='tel:5550100100']", "(555) 010-0100"
    assert_select "a[href='mailto:maria@example.com']"
    assert_select "address", /Austin, TX 78701/
    assert_select "#property-#{as_business(@business) { client.properties.first.uid }}", /Billing.*Gate code 1234/m
    assert_select ".badge", "weekly"
  end

  test "a name and a phone is enough" do
    as_member(@owner)
    post admin_clients_path, params: { client: { display_name: "Sam", contact_methods_attributes: { "0" => { kind: "phone", value: "5550100199" }, "1" => { kind: "email", value: "" } },
                                                 properties_attributes: { "0" => { address_line1: "", country: "US" } } } }
    client = as_business(@business) { Client.find_by!(display_name: "Sam") }
    assert_redirected_to admin_client_path(client)
    assert_empty as_business(@business) { client.properties.to_a }
  end

  test "invalid input re-renders with errors" do
    as_member(@owner)
    post admin_clients_path, params: { client: { display_name: "", contact_methods_attributes: { "0" => { kind: "email", value: "" } } } }
    assert_response :unprocessable_content
    assert_select ".banner-danger", /Add an email or a phone number/
    assert_select "input[name='client[contact_methods_attributes][1][kind]'][value=phone]", 1, "blank rows are offered again"
  end

  test "editing, archiving, restoring" do
    client = create_client
    as_member(@owner)
    get edit_admin_client_path(client)
    assert_response :success
    patch admin_client_path(client), params: { client: { company_name: "Lopez Rentals" } }
    assert_redirected_to admin_client_path(client)
    assert_equal "Lopez Rentals", client.reload.company_name

    patch archive_admin_client_path(client)
    assert client.reload.archived?
    get admin_clients_path
    assert_select "#client-#{client.uid}", false
    get admin_clients_path(archived: 1)
    assert_select "#client-#{client.uid}"
    patch restore_admin_client_path(client)
    assert_not client.reload.archived?
  end

  test "deleting a client without documents" do
    client = create_client
    as_member(@owner)
    delete admin_client_path(client)
    assert_redirected_to admin_clients_path
    assert_empty as_business(@business) { Client.all }
  end

  test "duplicate suggestions match on email or phone" do
    maria = create_client(phone: "(555) 010-0100")
    as_member(@owner)
    post matches_admin_clients_path, params: { phone: [ "+1 555 010 0100" ] }
    assert_select "turbo-stream[target=client_matches]", /Maria Lopez/
    assert_select "a[href='#{admin_client_path(maria)}']", "Open"

    post matches_admin_clients_path(inline: 1), params: { phone: [ "+1 555 010 0100" ] }
    assert_select "a[data-turbo-frame=new_client][href=?]", picked_admin_client_path(maria, inline: 1), "Use this client"

    post matches_admin_clients_path(except: maria.uid), params: { phone: [ "5550100100" ] }
    assert_select "turbo-stream[target=client_matches] li", false
  end

  test "background lookups leave the session cookie alone, so a racing submit keeps its flash" do
    create_client(phone: "(555) 010-0100")
    as_member(@owner)
    get admin_clients_path
    assert response.headers["Set-Cookie"].to_s.include?("_session"), "ordinary pages still write the session"

    post matches_admin_clients_path, params: { phone: [ "5550100100" ] }
    assert_response :success
    assert_not response.headers["Set-Cookie"].to_s.include?("_session")
    post search_admin_clients_path, params: { q: "maria" }, as: :json
    assert_response :success
    assert_not response.headers["Set-Cookie"].to_s.include?("_session")
  end

  test "inline creation hands the client back to the picker" do
    as_member(@owner)
    get new_admin_client_path(inline: 1)
    assert_select "turbo-frame#new_client form[action=?]", admin_clients_path(inline: 1)
    assert_select "#app-sidebar", false, "inline responses skip the layout"

    post admin_clients_path(inline: 1), params: { client: client_params }
    client = as_business(@business) { Client.find_by!(display_name: "Maria Lopez") }
    assert_redirected_to picked_admin_client_path(client, inline: 1)
    follow_redirect!
    assert_select "turbo-frame#new_client [data-controller=client-picked]" do |elements|
      assert_equal client.uid, JSON.parse(elements.first["data-client-picked-client-value"])["uid"]
    end
  end

  test "another business's clients are not reachable" do
    theirs = create_client("Theirs", business: businesses(:two))
    as_member(@owner)
    get admin_client_path(theirs)
    assert_response :not_found
    patch archive_admin_client_path(theirs)
    assert_response :not_found
    post matches_admin_clients_path, params: { phone: [ "5550100100" ] }
    assert_select "turbo-stream[target=client_matches] li", false
  end

  test "the sidebar links to clients for office roles" do
    as_member(@owner)
    get admin_root_path
    assert_select "nav a[href='#{admin_clients_path}']", "Clients"
  end

  test "pickers never offer or accept archived clients" do
    maria = create_client(phone: "(555) 010-0100")
    as_business(@business) { maria.archive! }
    as_member(@owner)
    post matches_admin_clients_path(inline: 1), params: { phone: [ "5550100100" ] }
    assert_select "turbo-stream[target=client_matches] li", false
    post matches_admin_clients_path, params: { phone: [ "5550100100" ] }
    assert_select "turbo-stream[target=client_matches]", /Maria Lopez/, "the full-page warning still mentions them"
    get picked_admin_client_path(maria, inline: 1)
    assert_select "turbo-frame#new_client", /archived/
    assert_select "[data-controller=client-picked]", false
  end

  test "too many tags are explained beside the tags field" do
    client = create_client
    as_member(@owner)
    patch admin_client_path(client), params: { client: { tag_list: (1..21).map { "t#{_1}" }.join(",") } }
    assert_response :unprocessable_content
    assert_select "input#client_tag_list[aria-invalid=true]"
    assert_select ".error-text", /at most 20 tags/
  end

  test "client details are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("client" => { "display_name" => "Maria", "notes" => "n", "tag_list" => "vip",
                                           "contact_methods_attributes" => { "0" => { "kind" => "phone", "value" => "555" } },
                                           "properties_attributes" => { "0" => { "address_line1" => "1 Main", "access_notes" => "gate", "city" => "Austin" } } },
                             "phone" => [ "555" ])
    assert_equal "[FILTERED]", filtered.dig("client", "display_name")
    assert_equal "[FILTERED]", filtered.dig("client", "contact_methods_attributes", "0", "value")
    assert_equal "phone", filtered.dig("client", "contact_methods_attributes", "0", "kind")
    assert_equal "[FILTERED]", filtered.dig("client", "properties_attributes", "0", "address_line1")
    assert_equal "[FILTERED]", filtered.dig("client", "properties_attributes", "0", "access_notes")
    assert_equal "[FILTERED]", filtered["phone"]
  end
end
