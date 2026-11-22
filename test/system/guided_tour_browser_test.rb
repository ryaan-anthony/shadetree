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

  # Waits for signing in to land (a technician goes /admin, then My day) before the test visits
  # anything: on CI a visit to the same URL while that redirect was still loading merged with it,
  # and the page lost its input.
  def sign_in_as(user)
    visit new_user_session_path
    sign_in_with_form(user.email, "password123")
    assert_selector "#main h1"
    wait_for_controllers
  end

  # Presses Tab until the focused element's text is `text` (keyboard only, no clicks).
  def tab_to(text, limit: 60)
    limit.times do
      return if evaluate_script("document.activeElement?.textContent?.trim()") == text

      page.send_keys(:tab)
    end
    seen = evaluate_script("[...document.querySelectorAll('a[href], button, [tabindex]')].filter((e) => e.getClientRects().length).map((e) => e.textContent.trim().slice(0, 30)).join(' | ')")
    flunk "Tab never reached #{text.inspect}. On the page: #{seen}. Main: #{evaluate_script("document.getElementById('main')?.innerText?.slice(0, 300)")}"
  end

  def focused_id = evaluate_script("document.activeElement?.id")
  def assert_stop(count, title)
    assert_selector "#tour[role=dialog]", visible: true
    assert_selector "#tour-count", text: count
    assert_selector "#tour-title", text: title
    assert_equal "tour", focused_id, "focus moves into each stop"
  end

  # Like input_reaches_page?: a deadline, not Timeout around database calls.
  def wait_for_status(status, stop: nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until @membership.reload.tour_status == status && (stop.nil? || @membership.tour_stop == stop)
      flunk "tour stayed #{[ @membership.tour_status, @membership.tour_stop ].inspect}, expected #{[ status, stop ].inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  end

  # Starts it the way a person does, from Help. (Visiting ?tour=start directly can be undone by
  # the input check's reload, which loads the URL after the tour has tidied the parameter away.)
  def start_from_help
    click_on "Help"
    click_on "Take the tour again"
    assert_selector "#tour[role=dialog]", visible: true
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

    assert_selector "#tour-pointing", text: "Pointing at: Get to your first quote", visible: :all
    page.send_keys(:f6) # into the checklist: its first link, never Hide
    assert_equal "Add details", evaluate_script("document.activeElement.textContent.trim()")
    page.send_keys(:f6)
    assert_equal "tour", focused_id

    [ [ "Stop 2 of 6", "Requests" ], [ "Stop 3 of 6", "Quotes" ], [ "Stop 4 of 6", "Schedule" ], [ "Stop 5 of 6", "Invoices" ], [ "Stop 6 of 6", "Settings" ] ].each do |count, title|
      tab_to "Next"
      page.send_keys(:enter)
      assert_stop count, title
      assert_selector "[data-tour=#{title.downcase}].tour-target"
      assert_selector "#tour-pointing", text: "Pointing at: #{title}, in the menu", visible: :all
    end
    wait_for_status "started", stop: "settings" # recorded in order

    page.send_keys(:f6) # to what it points at, and back
    assert_equal "Settings", evaluate_script("document.activeElement.textContent.trim()")
    page.send_keys(:f6)
    assert_equal "tour", focused_id
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
    visit admin_root_path
    start_from_help
    assert_stop "Stop 1 of 6", "Start here"
    assert_no_current_path(/tour=/) # a reload doesn't start it again
    click_on "Next"
    assert_stop "Stop 2 of 6", "Requests"
    page.send_keys(:f6) # Escape works from what it points at, too
    page.send_keys(:escape)
    assert_no_selector "#tour", visible: true
    wait_for_status "skipped", stop: "requests"

    start_from_help
    page.send_keys(:escape)
    assert_no_selector "#tour", visible: true
    assert_equal "H1", evaluate_script("document.activeElement.tagName"), "started with the page, so focus goes to its heading"

    start_from_help
    within("#setup-client") { click_on "Add a client" } # nothing covers or blocks the page
    assert_current_path new_admin_client_path(from: "setup")
  end

  test "it resumes after a look at the sample quote; following another link ends it there" do
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
    wait_for_status "started", stop: "quotes"

    click_on "Back"
    assert_stop "Stop 2 of 6", "Requests"
    find("[data-tour=requests]").click # the highlighted link: leaving ends the tour where it was
    assert_selector "h1", text: "Requests"
    wait_for_status "skipped", stop: "requests"
    visit admin_root_path
    assert_no_selector "#tour", visible: true
  end

  test "at 400% zoom the sheet never covers what it points at" do
    sign_in_as users(:one)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 213, deviceScaleFactor: 1, mobile: false)
    visit admin_root_path
    execute_script("document.querySelector('#help-menu ~ .menu a[href$=\"tour=start\"]').click()") # the menu runs off a screen this short
    assert_selector "#tour[role=dialog]", visible: true
    covered = <<~JS
      (() => { const sheet = document.getElementById("tour").getBoundingClientRect().top
               const target = document.querySelector(".tour-target").getBoundingClientRect()
               return target.top >= sheet || target.bottom <= 0 })()
    JS
    assert_selector "#tour.tour-sheet"
    sleep 0.3 # scrolling settles
    assert_not evaluate_script(covered), "the checklist is visible above the sheet"
    click_on "Next"
    assert_stop "Stop 2 of 6", "Requests"
    sleep 0.3
    assert_operator evaluate_script("document.querySelector('.tour-target').getBoundingClientRect().bottom"), :<=,
                    evaluate_script("document.getElementById('tour').getBoundingClientRect().top") + 1
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "on a phone it's a bottom sheet that steps through the menu, without motion when that's asked" do
    page.driver.browser.manage.window.resize_to(390, 844)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    sign_in_as users(:one)
    visit admin_root_path
    start_from_help
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
    # By keyboard: on CI, clicks on this page were sometimes lost entirely (no request reached
    # the server, focus stayed on <body>), the Chrome input problem the input check works around.
    tab_to "Show me around"
    page.send_keys(:enter)
    assert_stop "Stop 1 of 3", "My day"
    assert_selector "[data-tour=today].tour-target"
    tab_to "Next"
    page.send_keys(:enter)
    assert_stop "Stop 2 of 3", "Coming up"
    tab_to "Next"
    page.send_keys(:enter)
    assert_stop "Stop 3 of 3", "Help"
    tab_to "Done"
    page.send_keys(:enter)
    assert_no_selector "#tour", visible: true
    wait_for_status "finished"
  end

  # Loads a page without the input check's recovery reload: the first load already marks its tip seen.
  def open_page(path)
    page.visit(path)
    wait_for_controllers
  end

  def wait_for_tip(key, field)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until @membership.reload.tips.dig(key, field)
      flunk "#{key} never #{field}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  end

  test "a first-time tip shows once, is hidden by keyboard, and isn't kept for Back" do
    sign_in_as users(:one)
    open_page admin_service_requests_path
    assert_selector "#tip-requests[role=note]", text: "Requests from your online form", visible: true
    wait_for_tip "requests", "seen_at"
    click_on "Invoices" # a Turbo visit, then Back to the cached page
    assert_selector "#tip-invoices", visible: true
    page.go_back
    assert_selector "h1", text: "Requests"
    assert_no_selector "#tip-requests", visible: :all

    open_page admin_invoices_path
    assert_no_selector ".tip", visible: :all, wait: 0 # shown once already
    open_page admin_schedule_path
    tab_to "Got it"
    page.send_keys(:enter)
    assert_no_selector "#tip-schedule"
    assert_equal "H1", evaluate_script("document.activeElement.tagName")
    wait_for_tip "schedule", "dismissed_at"
  end

  test "tips wait while the tour is away at the sample quote, come back from Help, and hide on a phone" do
    sign_in_as users(:one)
    visit admin_root_path
    click_on "Take a 2-minute tour"
    click_on "Next"
    click_on "Next"
    click_on "See what a client sees" # the tour keeps its place
    assert_text "Jordan Rivera"
    open_page admin_invoices_path
    assert_selector "#tip-invoices", visible: :hidden
    open_page admin_root_path
    assert_stop "Stop 3 of 6", "Quotes"
    click_on "End tour"
    open_page admin_invoices_path
    assert_selector "#tip-invoices", visible: true

    click_on "Help"
    click_on "Show tips again"
    assert_text "Tips will show again"
    page.driver.browser.manage.window.resize_to(390, 844)
    open_page admin_service_requests_path
    within("#tip-requests") { click_on "Got it" }
    assert_no_selector "#tip-requests"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
