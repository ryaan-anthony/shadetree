require "application_system_test_case"

# PLT-19 in a browser: the kit's menus, tabs and segmented controls on real pages, by keyboard,
# with an axe check (WCAG 2.1 A/AA) while they're in use.
class KitControlsTest < ApplicationSystemTestCase
  AXE = Pathname(Gem.loaded_specs.fetch("axe-core-api").full_gem_path).join("node_modules/axe-core/axe.min.js")

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    visit new_user_session_path
    sign_in_with_form(@owner.email, "password123")
    assert_text "Home"
  end

  def assert_axe_clean(label)
    execute_script(AXE.read) unless evaluate_script("typeof window.axe === 'object'")
    problems = evaluate_async_script(<<~JS)
      const done = arguments[0]
      axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "best-practice"] } })
        .then((r) => done(r.violations.map((v) => `${v.id} (${v.help}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`)))
    JS
    assert_empty problems, "axe on #{label}:\n#{problems.join("\n")}"
  end

  def focused_text = evaluate_script("document.activeElement.textContent").squish

  def sent_quote
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Quote.start(client:, created_by: @owner).tap do |quote|
        quote.title = "Spring cleanup"
        quote.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "240", "taxable" => "0" } ])
        quote.save!
        quote.mark_sent!(by: @owner, channel: "link")
      end
    end
  end

  test "the quote menu: keyboard, one line per item, and axe while open" do
    visit admin_quote_path(sent_quote)
    button = find_button("More actions")
    button.send_keys(:down)
    assert_equal "true", button["aria-expanded"]
    assert_equal "Download PDF", focused_text
    page.send_keys(:end)
    assert_equal "Archive", focused_text
    heights = [ "Download PDF", "Duplicate for another client" ].map { evaluate_script("arguments[0].getBoundingClientRect().height", find(".menu-item", text: _1)) }
    assert_equal heights.first, heights.last, "\"Duplicate for another client\" fits on one line"
    assert_axe_clean "the quote page, menu open"

    page.send_keys(:escape)
    assert_equal "false", button["aria-expanded"]
    assert_equal button["aria-label"], evaluate_script("document.activeElement.getAttribute('aria-label')"), "Escape returns to the button"

    button.click
    find(".menu-item", text: "Duplicate for another client").click
    assert_selector "dialog#duplicate-for[open]"
    assert_selector "##{button["aria-controls"]}[hidden]", visible: :all
  end

  # Retries the block (Capybara's wait time) until it's truthy: for layout that settles after a
  # resize, a click or a resize event.
  def assert_eventually(message)
    page.document.synchronize { yield || raise(Capybara::ExpectationNotMet, message.call) }
  rescue Capybara::ExpectationNotMet => e
    flunk e.message
  end

  def resize_window(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
    assert_eventually(-> { "the window is #{width} wide" }) { evaluate_script("innerWidth") == width }
  end

  def assert_menu_on_screen(label)
    box = -> { evaluate_script("(() => { const r = document.querySelector('.menu:not([hidden])').getBoundingClientRect(); return [r.left, r.right, document.documentElement.clientWidth] })()") }
    assert_eventually(-> { "#{label}: the open menu spans #{box.call.first(2)}, the screen 0..#{box.call.last}" }) do
      left, right, width = box.call
      left >= 0 && right <= width
    end
  end

  test "the menu fits a phone screen" do
    resize_window(390, 844)
    visit admin_quote_path(sent_quote)
    find_button("More actions").click
    assert_menu_on_screen "at 390px"

    page.send_keys(:escape)
    resize_window(440, 844) # opened a little wider, then the phone turns: it moves back on
    find_button("More actions").click
    resize_window(390, 844)
    assert_menu_on_screen "resized to 390px while open"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "the schedule's segmented controls: Color by by keyboard, Day/Week as links, and axe" do
    visit admin_schedule_path
    within("#schedule-color") do
      assert_selector ".segmented[role=group][aria-labelledby=schedule-color-label] button.segment[aria-pressed=true]", text: "Person"
      find("button.segment", text: "Status").send_keys(:enter)
    end
    assert_selector "#schedule-color button.segment[aria-pressed=true]", text: "Status"
    assert_equal "Status", focused_text, "focus comes back to the chosen option"
    within("ul.segmented[aria-label=View]") { click_link "Day" }
    assert_selector "ul.segmented a.segment[aria-current=page]", text: "Day"
    assert_axe_clean "the schedule"
  end

  test "list tabs by keyboard: the pressed tab is announced and keeps focus" do
    sent_quote
    visit admin_quotes_path
    assert_no_selector "nav.tabs button.tab[value=declined]" # PLT-19: none declined, so hidden
    find("nav.tabs button.tab[value=awaiting]").send_keys(:enter)
    assert_selector "nav.tabs button.tab[value=awaiting][aria-pressed=true]"
    assert_selector "nav.tabs button.tab[value=all][aria-pressed=false]"
    assert_selector "nav.tabs button.tab[value=awaiting]:focus" # back on it once the results arrive
    assert_axe_clean "the quotes list"
  end

  test "services search as you type, and Enter still searches" do
    Tenancy.with_business(@business) do
      CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45")
      CatalogItem.create!(name: "Hedge trimming", unit: "hour", unit_price: "60")
    end
    visit admin_catalog_items_path
    assert_no_button "Search"
    find_field("Search your services").fill_in(with: "mow")
    assert_no_text "Hedge trimming"
    assert_text "Mowing"
    assert_equal "mow", find_field("Search your services").value, "the box is kept: only the results refresh"
    find_field("Search your services").fill_in(with: "hedge\n")
    assert_text "Hedge trimming"
    assert_no_text "Mowing"
    assert_axe_clean "the services list"
  end

  test "settings pages are a segmented control under the group tabs" do
    visit edit_admin_business_path(tab: "branding")
    within("#settings-nav") do
      assert_selector ".tabs a.tab[aria-current=true]", text: "Business"
      assert_selector "ul.segmented a.segment[aria-current=page]", text: "Branding"
      click_link "Hours"
    end
    assert_selector "#settings-nav ul.segmented a.segment[aria-current=page]", text: "Hours"
    assert_axe_clean "Hours"
  end

  # Owner, 2026-11-23: Requests search as you type too; the status region outside the frame says what's shown.
  test "requests search as you type and the result is announced" do
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Fence repair")
      ServiceRequest.create!(client:, source: "phone", description: "Gutter guards")
    end
    visit admin_service_requests_path
    assert_no_button "Search"
    find_field("Search requests").fill_in(with: "gutter")
    assert_no_text "Fence repair"
    assert_text "Gutter guards"
    assert_selector "#request_results_status[role=status]", text: "1 request matching gutter", visible: :all
    assert_current_path admin_service_requests_path # client names stay out of the URL
    assert_axe_clean "the requests list"
  end

  test "a settings group's pages wrap on a phone instead of scrolling" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit edit_admin_business_path(tab: "branding")
    widths = evaluate_script("(() => { const s = document.querySelector('#settings-nav ul.segmented'); return [s.scrollWidth, s.clientWidth, document.documentElement.scrollWidth] })()")
    assert_equal widths[1], widths[0], "nothing hidden sideways"
    assert_operator widths[2], :<=, 390
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
