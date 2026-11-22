require "application_system_test_case"

# #289: a button that saves or sends says what it's doing while the request runs, from one
# shared hook (app/javascript/submitting.js), so a slow request never looks like a dead button.
class SubmitFeedbackTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  # Stops the next submit after the shared hook has run (it listens first, in the capture
  # phase), so the label it chose can be read without sending anything.
  def hold_next_submit
    execute_script("document.addEventListener('submit', (e) => e.preventDefault(), { once: true })")
  end

  def label_of(button) = find_button(button, disabled: :all)["data-turbo-submits-with"]

  test "a real round trip shows the in-progress label, then the button and form are back to normal" do
    visit new_admin_catalog_item_path
    fill_in "Name", with: "Spraying"
    fill_in "Default price", with: "lots" # refused by the server: 422, the form again
    # Turbo renders the 422 in place; the window (and what it saw) survives.
    execute_script(<<~JS)
      window.seenLabels = []
      new MutationObserver(() => document.querySelectorAll("form button, form input[type=submit]").forEach((b) => window.seenLabels.push((b.value || b.textContent).trim())))
        .observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true })
    JS
    # The button's label may be "Add item" or "Add service" (#298 renames it); either says "Adding…".
    submit = "form[action='#{admin_catalog_items_path}'] [type=submit]"
    find(submit).click
    assert_selector ".banner-danger", text: /to fix/
    assert_includes evaluate_script("window.seenLabels"), "Adding…"
    assert_match(/\AAdd (item|service)\z/, find(submit).value)
    assert_no_selector "form[aria-busy]"
  end

  test "searches, menu items, icon-only buttons and buttons with their own label are left alone" do
    visit admin_jobs_path # the filters are submit buttons of a GET form
    hold_next_submit
    click_on "Completed"
    assert_nil label_of("Completed")

    as_business(@business) { 2.times { |i| CatalogItem.create!(name: "Item #{i}", unit_price: "10") } }
    visit admin_catalog_items_path
    hold_next_submit
    click_on "Move Item 0 down"
    assert_nil label_of("Move Item 0 down"), "icon-only: its aria-label names it, and its size stays"

    visit new_admin_client_path
    fill_in "Name", with: "Maria Lopez"
    execute_script("[...document.querySelectorAll('[type=submit]')].find((b) => (b.value || b.textContent).trim() === 'Add client').setAttribute('data-turbo-submits-with', 'Hang on…')")
    hold_next_submit
    click_on "Add client"
    assert_equal "Hang on…", label_of("Add client")

    quote = as_business(@business) do
      client = Client.create!(display_name: "Grace", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "10" } ]) && _1.save! }
                          .tap { _1.mark_sent!(by: users(:one), channel: "link") }
    end
    visit admin_quote_path(quote)
    click_on "More actions"
    hold_next_submit
    within(".menu") { click_on "Duplicate", exact: true }
    assert_nil find(".menu button", text: "Duplicate", exact_text: true, visible: :all)["data-turbo-submits-with"]
  end

  test "the label comes from the button's verb" do
    visit admin_clients_path
    label = ->(text) { evaluate_async_script("import('submitting').then((m) => arguments[0](m.submittingLabel(#{text.to_json})))") }
    assert_equal "Creating…", label.("Create invoice")
    assert_equal "Sending…", label.(" Send quote ")
    assert_equal "One moment…", label.("Whatever")
  end
end
