require "application_system_test_case"

# PLT-20: a detail page's side column (.rail) never breaks a date over two lines ("Nov 22, /
# 2026"), measured in the browser at 1280 px on the shared page list's detail pages.
class DetailRailsTest < ApplicationSystemTestCase
  setup do
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  test "rail dates stay on one line at 1280 px" do
    pages = StaffPages.build(businesses(:one), users(:one)).select(&:detail?)
    page.driver.browser.manage.window.resize_to(1280, 1000)
    railed = 0
    problems = pages.flat_map do |staff_page|
      visit staff_page.path
      wrapped = evaluate_script(<<~JS)
        [...document.querySelectorAll(".rail time")].filter((t) => t.getClientRects().length > 1).map((t) => t.textContent.trim())
      JS
      railed += 1 if has_css?(".rail time", wait: 0)
      wrapped.map { "#{staff_page}: #{_1.inspect} wraps" }
    end
    assert_operator railed, :>=, 10, "expected dates in the rails of most detail pages"
    assert_empty problems, problems.join("\n")
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
