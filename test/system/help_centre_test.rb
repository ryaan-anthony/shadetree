require "application_system_test_case"

# OPS-06: the help articles in a browser: both copies pass axe wide and at 360 px, the Help
# menu's search, suggestions appearing as a question's subject is typed, and "Was this helpful?".
class HelpCentreTest < ApplicationSystemTestCase
  include AxeHelpers

  SLUG = "get-help-from-shadetree"

  teardown { page.driver.browser.manage.window.resize_to(1400, 1400) } # the size every system test expects

  test "the public pages pass axe, wide and on a phone, and a no offers Contact us" do
    [ [ 1400, 1000 ], [ 360, 800 ] ].each do |size|
      page.driver.browser.manage.window.resize_to(*size)
      assert_accessible help_path, help_article_path(SLUG), help_path(q: "zebra crossing")
      assert_equal page.evaluate_script("document.documentElement.clientWidth"), page.evaluate_script("document.documentElement.scrollWidth"), "no sideways scroll at #{size.first}"
    end
    visit help_article_path(SLUG)
    within("#help-vote") { click_on "No" }
    within("#help-vote") { assert_link "Contact us", href: contact_path }
  end

  test "members search from the Help menu, get suggestions on a question, and vote" do
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    visit admin_support_tickets_path # a page without the sign-in toast
    click_on "Help"
    assert_no_selector ".menu[hidden] #help-menu-q", visible: :all
    assert_empty axe_problems("Help menu open")
    fill_in "Search help articles", with: "screenshots"
    find("#help-menu-q").send_keys(:enter)
    assert_selector "#help-results a", text: "Get help from the Shadetree team"
    assert_empty axe_problems("Results")

    visit new_admin_support_ticket_path(from: "/admin/quotes")
    assert_no_selector "#help-suggestions a"
    fill_in "Subject", with: "who sees my question"
    assert_selector "#help-suggestions a[target=_blank]", text: "Get help from the Shadetree team"
    assert_equal "who sees my question", find_field("Subject").value, "the draft stays"
    assert_empty axe_problems("Suggestions")

    visit admin_help_article_path(SLUG)
    assert_empty axe_problems("Article in the app")
    within("#help-vote") { click_on "No" }
    within("#help-vote") { assert_link "Ask Shadetree" }
  end
end
