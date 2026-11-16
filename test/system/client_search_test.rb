require "application_system_test_case"

# CLI-02 in a browser: search as you type, the archived tab, and the client picker with its
# quick-create handshake.
class ClientSearchSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    as_business(@business) do
      [ [ "Maria Lopez", "(555) 010-0100" ], [ "Sam Okafor", "555-010-0299" ] ].each do |name, phone|
        Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: phone } ])
      end
      Client.create!(display_name: "Old Okafor", contact_methods_attributes: [ { kind: "phone", value: "555-010-0300" } ]).archive!
    end
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "password123"
    click_on "Sign in"
    assert_text "Home"
  end

  test "typing filters the list in place, and the archived tab keeps working with search" do
    visit admin_clients_path
    fill_in "Search clients", with: "+1 555 010 0299"
    assert_no_text "Maria Lopez", wait: 5
    assert_text "Sam Okafor"
    assert_current_path admin_clients_path # search terms never go into the URL

    fill_in "Search clients", with: "okafor"
    assert_text "Sam Okafor"
    find("label.tab-radio", text: "Archived").click
    assert_text "Old Okafor"
    assert_no_text "Sam Okafor"

    fill_in "Search clients", with: "old"
    assert_text "Old Okafor", wait: 5
    assert find("input[name=archived][value='1']", visible: :all).checked?
  end

  test "the picker finds a client by keyboard, refuses an empty submit, and takes a new client" do
    visit styleguide_path(anchor: "pickers")
    within("#picker-demo") { click_on "Submit" }
    assert_nil find("#picker-demo")["data-submitted"], "an empty required picker blocks the submit"
    within("#picker-demo") do
      find("input[type=search]").fill_in(with: "maria")
      assert_selector "[role=option]", text: "Maria Lopez"
      find("input[type=search]").send_keys(:down, :enter)
      assert_text "Maria Lopez"
      maria = as_business(@business) { Client.find_by!(display_name: "Maria Lopez") }
      assert_equal maria.uid, find("input[type=hidden][name='demo[client]']", visible: :all).value

      click_on "Change"
      click_on "New client"
    end
    within("dialog[open]") do
      fill_in "Name", with: "Picker Person"
      find("input[type=tel]").fill_in(with: "555-777-1234")
      click_on "Add client"
    end
    assert_no_selector "dialog[open]"
    within("#picker-demo") { assert_text "Picker Person" }
    person = as_business(@business) { Client.find_by!(display_name: "Picker Person") }
    assert_equal person.uid, find("input[type=hidden][name='demo[client]']", visible: :all).value
  end

  test "a picker search that races a focus change still finishes" do
    visit styleguide_path(anchor: "pickers")
    within("#picker-demo") do
      input = find("input[type=search]")
      input.fill_in(with: "sam")
      # Focus leaves before the debounced search fires; it used to be dropped here.
      execute_script("arguments[0].blur()", input)
      assert_no_selector "[role=option]"
      # The search finished while the list was hidden.
      assert_selector "[data-client-picker-target=status]", text: "1 clients", visible: :all, wait: 5
      input.click
      assert_selector "[role=option]", text: "Sam Okafor"
    end
  end
end
