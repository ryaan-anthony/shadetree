require "application_system_test_case"

# JOB-05: the visit-email switches live on Settings → Messages (owner, 2026-11-22).
class VisitEmailSettingsSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    visit new_user_session_path
    sign_in_with_form(users(:one).email)
    assert_text "Home"
  end

  test "an owner turns booking emails off from Messages, and finds them there again" do
    visit edit_admin_business_path(tab: "documents")
    assert_no_text "Visit emails to clients"
    within("#settings-nav") { click_on "Messages" }
    within("#visit-emails-form") do
      assert_checked_field "Visit booked"
      uncheck "Visit booked"
      click_on "Save visit emails"
    end
    assert_text "Visit emails saved."
    assert_current_path admin_message_templates_path
    assert_unchecked_field "Visit booked"
    assert_checked_field "Reminder the day before"
    assert_not @business.reload.client_visit_email?(:scheduled)
  end
end
