require "application_system_test_case"

# MKT-01: the public site's calls to action lead where they say, on a phone too.
class MarketingTest < ApplicationSystemTestCase
  test "Start free from the home page goes to sign-up, and the bottom box brings the email along" do
    visit root_path
    within("main") { click_on "Start free", match: :first }
    assert_selector "h1", text: "Create your account"

    visit root_path
    fill_in "Your email", with: "ana@example.com"
    within("main") { find("button", text: "Start free").click }
    assert_field "Work email", with: "ana@example.com"
  end

  test "See how it works scrolls to the steps, and Compare plans opens pricing" do
    visit root_path
    click_on "See how it works"
    assert_selector "#how-it-works h2"
    click_on "Compare plans"
    assert_current_path pricing_path
  end

  test "Features from the navigation shows the screenshots, and its links jump to each section" do
    visit root_path
    within("header") { click_on "Features" }
    assert_selector "h1", text: "Everything between the first call and getting paid"
    click_on "Invoices and payments"
    assert_selector "#invoicing img"
  end

  test "on a phone the links fold into a menu" do
    page.current_window.resize_to(390, 800)
    visit root_path
    assert_no_selector "header ul.md\\:flex a", text: "Pricing", visible: true
    find("summary[aria-label=Menu]").click
    within("details") { click_on "Pricing" }
    assert_current_path pricing_path
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
