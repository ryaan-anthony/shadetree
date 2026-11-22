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

  # Stops the submit after the shared hook has run (it listens first, in the capture phase), so
  # the label it chose can be read before the request would start.
  def label_chosen_for(button)
    execute_script("document.addEventListener('submit', (e) => e.preventDefault(), { once: true })")
    click_on button
    find_button(button)["data-turbo-submits-with"]
  end

  test "submit buttons get an in-progress label; a button's own label wins; searches don't" do
    visit new_admin_client_path
    fill_in "Name", with: "Maria Lopez"
    assert_equal "Adding…", label_chosen_for("Add client")

    visit admin_clients_path
    assert_equal "Creating…", evaluate_async_script("import('submitting').then((m) => arguments[0](m.submittingLabel('Create invoice')))")
    assert_equal "Sending…", evaluate_async_script("import('submitting').then((m) => arguments[0](m.submittingLabel(' Send quote ')))")
    assert_equal "Saving…", evaluate_async_script("import('submitting').then((m) => arguments[0](m.submittingLabel('Whatever')))")
    assert_no_selector "form[method=get] [data-turbo-submits-with]"
  end
end
