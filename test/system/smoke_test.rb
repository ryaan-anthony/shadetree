require "application_system_test_case"

# Proves the browser-based test pipeline works end to end in CI.
# Feature specs add their own system tests alongside their code.
class SmokeTest < ApplicationSystemTestCase
  test "visitor can open the home page" do
    visit root_path

    assert_selector "h1"
  end

  test "visitor can reach the sign-in form" do
    visit new_user_session_path

    assert_selector "form input[type=email]"
    assert_selector "form input[type=password]"
  end
end
