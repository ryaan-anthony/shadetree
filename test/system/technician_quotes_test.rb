require "application_system_test_case"

# QTE-07: "Ready for review" saves what's still being typed before handing the draft over. A
# built-in Technician quotes the requests given to them and the office sends it (owner, 2026-11-22).
class TechnicianQuotesSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "limits" => { "team_members" => nil } })
    owner = users(:one)
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    Tenancy.with_business(@business) do
      BusinessUser.create!(user: @tech, business: @business, role: "technician")
      item = CatalogItem.create!(name: "Weekly mowing", unit: "visit", unit_price: "45")
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
      request = ServiceRequest.create!(client:, source: "phone", description: "Mowing", services: [ { "catalog_item_id" => item.id, "name" => item.name } ])
      RequestFollowUp.assign!(request, { user: @tech, scheduled_on: @business.today }, by: owner).done!(by: @tech)
      @quote = request.create_quote!(by: @tech, once: true)
    end
    visit new_user_session_path
    sign_in_with_form(@tech.email, "password123")
    assert_text "My day"
  end

  test "typing then Ready for review at once keeps what was typed, then hands it over" do
    visit edit_admin_quote_path(@quote)
    assert_text "Draft for Maria Lopez"
    fill_in "Title", with: "Mowing, May to September"
    assert_no_link href: new_admin_quote_send_path(@quote)
    click_on "Ready for review"
    assert_text "Marked ready for review. The office will check it and send it."
    assert_text "Ready for review: the office sends it"
    quote = Tenancy.with_business(@business) { @quote.reload }
    assert_equal "Mowing, May to September", quote.title
    assert quote.ready_for_review?
  end
end
