require "application_system_test_case"

# CLI-04 (owner, 2026-11-22): Create quote on a request with an unsent draft opens that draft.
class RequestQuoteSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @request_record = Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Fence repair")
    end
    visit new_user_session_path
    sign_in_with_form(users(:one).email)
    assert_text "Home"
  end

  test "a second Create quote opens the draft the first made" do
    visit admin_service_request_path(@request_record)
    click_on "Create quote"
    assert_text "Nothing is sent until you send it."
    quote = Tenancy.with_business(@business) { @request_record.quotes.sole }
    assert_current_path edit_admin_quote_path(quote)

    visit admin_service_request_path(@request_record)
    click_on "Create quote"
    assert_text "This request already has a draft quote, #{quote.number}."
    assert_current_path edit_admin_quote_path(quote)
    assert_equal 1, Tenancy.with_business(@business) { @request_record.quotes.count }
  end
end
