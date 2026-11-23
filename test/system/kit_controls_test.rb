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

  test "the menu fits a phone screen" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit admin_quote_path(sent_quote)
    find_button("More actions").click
    box = evaluate_script("(() => { const r = document.querySelector('.menu:not([hidden])').getBoundingClientRect(); return [r.left, r.right] })()")
    assert_operator box.first, :>=, 0
    assert_operator box.last, :<=, 390
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
