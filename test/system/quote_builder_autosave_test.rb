require "application_system_test_case"

# #289: the builder saves one way, as you go; it never loses work by navigating away. Each step
# waits on the save status (never a sleep) and confirms typed text has arrived first.
class QuoteBuilderAutosaveTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Quote.start(client:).tap do |quote|
        quote.sync_line_items([ { "key" => "k1", "name" => "Spraying", "quantity" => "1", "unit_price" => "80" } ])
        quote.save!
      end
    end
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  def type_title(text)
    field = find_field("Title")
    field.fill_in(with: text)
    assert_field "Title", with: text
  end

  def saved_title = as_business(@business) { @quote.reload.title }

  test "an edit saves by itself and is there after a reload" do
    visit edit_admin_quote_path(@quote)
    assert_no_button "Save draft" # autosave is running, so its fallback is hidden
    type_title("Ant treatment")
    assert_selector "#save_status", text: "Saved"
    visit edit_admin_quote_path(@quote)
    assert_field "Title", with: "Ant treatment"
  end

  test "leaving for another page waits for the save" do
    visit edit_admin_quote_path(@quote)
    type_title("Wasp nest")
    within("nav[aria-label=Primary]") { click_on "Clients" }
    assert_selector "h1", text: "Clients"
    assert_equal "Wasp nest", saved_title
  end

  test "Send while a save is on its way goes once it's saved" do
    visit edit_admin_quote_path(@quote)
    type_title("Mice")
    click_on "Send quote"
    assert_selector "h1", text: "Send quote #{@quote.number}"
    assert_equal "Mice", saved_title
  end

  test "a refused save is shown as a failure, and leaving asks first; staying keeps the work" do
    visit edit_admin_quote_path(@quote)
    type_title("Fleas")
    qty = find("#line-qty-k1")
    qty.fill_in(with: "two")
    assert_field "line-qty-k1", with: "two"
    assert_selector "#save_status[data-state=error]", text: "Not saved: fix the errors above"
    assert_selector "#autosave-note [data-state=error]", text: "Not saved"

    dismiss_confirm("Your changes aren't saved. Leave anyway?") do
      within("nav[aria-label=Primary]") { click_on "Clients" }
    end
    assert_selector "h1", text: "Quote #{@quote.number}"
    assert_field "Title", with: "Fleas"
  end
end
