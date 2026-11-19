require "application_system_test_case"

# CLI-01 in a browser: nested contact and property rows, the single billing address, and
# duplicate suggestions while typing.
class ClientsSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "(555) 010-0100" } ])
    end
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  test "adding a client with two phones and two properties" do
    visit new_admin_client_path
    fill_in "Name", with: "Lopez Rentals"
    # The duplicate lookup runs after typing; on a slow headless Chrome keys can be lost, or the
    # first lookup can be slow on a cold runner. Type again until the match shows (typing the
    # same number again is harmless); a real failure still fails, after 20 seconds.
    phone = first("input[type=tel]")
    page.document.synchronize(20) do
      phone.fill_in(with: "555 010 0100") unless phone.value == "555 010 0100"
      raise Capybara::ExpectationNotMet, "no duplicate match shown (the box holds #{phone.value.inspect})" unless page.has_text?("A client already has this email or phone.", wait: 4)
    end
    assert_link "Open", href: %r{/admin/clients/}

    click_on "Add phone"
    all("input[type=tel]").last.fill_in with: "555-010-0222"
    click_on "Add email"
    click_on "Remove this email", match: :first

    fill_in "Street address", with: "1 Main St"
    click_on "Add property"
    all("input[name$='[address_line1]']").last.fill_in with: "9 Oak Ave"
    all("input[name$='[billing]'][type=checkbox]").first.check
    all("input[name$='[billing]'][type=checkbox]").last.check
    assert_not all("input[name$='[billing]'][type=checkbox]").first.checked?

    click_on "Add client"
    assert_text "Lopez Rentals added."
    client = as_business(@business) { Client.find_by!(display_name: "Lopez Rentals") }
    as_business(@business) do
      assert_equal %w[5550100100 5550100222], client.contact_methods.map(&:normalized)
      assert_equal "9 Oak Ave", client.billing_property.address_line1
      assert_equal 2, client.properties.count
    end
  end
end
