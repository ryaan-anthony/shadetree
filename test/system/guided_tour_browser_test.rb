require "application_system_test_case"

# ACC-08: the guided tour in a browser: keyboard only from the offer to the checklist, Escape,
# resuming after a look elsewhere, the phone's bottom sheet stepping through the menu, reduced
# motion, and the technician's short tour.
class GuidedTourBrowserTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(onboarded_at: nil, phone: nil)
    @membership = business_users(:one)
    @membership.update!(tour_status: "offered", tour_offered_at: Time.current)
  end

  def sign_in_as(user)
    visit new_user_session_path
    sign_in_with_form(user.email, "password123")
  end

  # Presses Tab until the focused element's text is `text` (keyboard only, no clicks).
  def tab_to(text, limit: 60)
    limit.times do
      return if evaluate_script("document.activeElement?.textContent?.trim()") == text

      page.send_keys(:tab)
    end
    flunk "Tab never reached #{text.inspect}"
  end

  def focused_id = evaluate_script("document.activeElement?.id")
  def assert_stop(count, title)
    assert_selector "#tour[role=dialog]", visible: true
    assert_selector "#tour-count", text: count
    assert_selector "#tour-title", text: title
    assert_equal "tour", focused_id, "focus moves into each stop"
  end

  def wait_for_status(status)
    Timeout.timeout(5) { sleep 0.05 until @membership.reload.tour_status == status }
  rescue Timeout::Error
    flunk "tour status stayed #{@membership.tour_status.inspect}, expected #{status.inspect}"
  end

  test "keyboard only: take the tour from the offer, through every stop, to the first checklist step" do
    sign_in_as users(:one)
    visit admin_root_path
    tab_to "Take a 2-minute tour"
    page.send_keys(:enter)
    assert_stop "Stop 1 of 6", "Start here"
    assert_selector "[data-tour=checklist].tour-target"
    assert_no_selector "#tour-offer", visible: true
    wait_for_status "started"

    [ [ "Stop 2 of 6", "Requests" ], [ "Stop 3 of 6", "Quotes" ], [ "Stop 4 of 6", "Schedule" ], [ "Stop 5 of 6", "Invoices" ], [ "Stop 6 of 6", "Settings" ] ].each do |count, title|
      tab_to "Next"
      page.send_keys(:enter)
      assert_stop count, title
      assert_selector "[data-tour=#{title.downcase}].tour-target"
    end
    tab_to "Back"
    page.send_keys(:enter)
    assert_stop "Stop 5 of 6", "Invoices"
    tab_to "Next"
    page.send_keys(:enter)

    tab_to "Next: Add your business details"
    page.send_keys(:enter)
    assert_no_selector "#tour", visible: true
    assert_equal "Add details", evaluate_script("document.activeElement.textContent.trim()"), "focus lands on the step"
    wait_for_status "finished"
    assert_equal "settings", @membership.tour_stop
  end

  test "Escape ends it where you are, focus comes back, and the page stays usable while it's open" do
    sign_in_as users(:one)
    visit admin_root_path(tour: "start")
    assert_stop "Stop 1 of 6", "Start here"
    assert_no_current_path(/tour=/) # a reload doesn't start it again
    click_on "Next"
    assert_stop "Stop 2 of 6", "Requests"
    page.send_keys(:escape)
    assert_no_selector "#tour", visible: true
    assert_equal "H1", evaluate_script("document.activeElement.tagName")
    wait_for_status "skipped"
    assert_equal "requests", @membership.tour_stop

    visit admin_root_path(tour: "start")
    assert_stop "Stop 1 of 6", "Start here"
    within("#setup-client") { click_on "Add a client" } # nothing covers or blocks the page
    assert_current_path new_admin_client_path(from: "setup")
  end

  test "it resumes after a look at the sample quote" do
    sign_in_as users(:one)
    visit admin_root_path
    click_on "Take a 2-minute tour"
    click_on "Next"
    click_on "Next"
    assert_stop "Stop 3 of 6", "Quotes"
    click_on "See what a client sees"
    assert_text "Jordan Rivera"
    visit admin_root_path
    assert_stop "Stop 3 of 6", "Quotes"
    click_on "End tour"
    visit admin_root_path
    assert_no_selector "#tour", visible: true
  end

  test "on a phone it's a bottom sheet that steps through the menu, without motion when that's asked" do
    page.driver.browser.manage.window.resize_to(390, 844)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    sign_in_as users(:one)
    visit admin_root_path(tour: "start")
    assert_stop "Stop 1 of 6", "Start here"
    assert_selector "#tour.tour-sheet"
    assert_operator evaluate_script("parseFloat(getComputedStyle(document.getElementById('tour')).animationDuration)"), :<, 0.01
    assert_no_selector "#app-sidebar[data-open=true]"
    click_on "Next"
    assert_stop "Stop 2 of 6", "Requests"
    assert_selector "#app-sidebar[data-open=true] [data-tour=requests].tour-target"
    4.times { click_on "Next" }
    assert_stop "Stop 6 of 6", "Settings"
    sheet_top = evaluate_script("document.getElementById('tour').getBoundingClientRect().top")
    assert_operator evaluate_script("document.querySelector('[data-tour=settings]').getBoundingClientRect().bottom"), :<=, sheet_top + 1, "the sheet doesn't hide the link"
    click_on "End tour"
    assert_no_selector "#app-sidebar[data-open=true]"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a technician takes the short My day tour from the welcome" do
    tech = User.create!(email: "crew@example.com", password: "password123", first_name: "Crew", confirmed_at: Time.current)
    @membership = BusinessUser.create!(business: @business, user: tech, role: "technician")
    sign_in_as tech
    visit admin_my_day_path
    click_on "Show me around"
    assert_stop "Stop 1 of 3", "My day"
    assert_selector "[data-tour=today].tour-target"
    click_on "Next"
    assert_stop "Stop 2 of 3", "Coming up"
    click_on "Next"
    assert_stop "Stop 3 of 3", "Help"
    click_on "Done"
    assert_no_selector "#tour", visible: true
    wait_for_status "finished"
  end
end
