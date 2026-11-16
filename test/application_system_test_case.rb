require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_option("goog:loggingPrefs", { browser: "ALL" }) # so a failure can show the console
  end

  # Icon-only buttons are named with aria-label; let click_on and assert_button find them.
  Capybara.enable_aria_label = true

  # When a test fails, show what the server did meanwhile (requests, status, timing) and the
  # browser's console, so a CI-only failure can be diagnosed from the log.
  teardown do
    next if passed?

    log = Rails.root.join("log/test.log")
    lines = File.exist?(log) ? File.readlines(log).last(400).grep(/Started|Completed|Error|Processing by/).last(40) : []
    puts "\n--- server requests before the failure ---", lines.join
    console = page.driver.browser.respond_to?(:logs) ? (page.driver.browser.logs.get(:browser) rescue []) : [] # rubocop:disable Style/RescueModifier
    puts "--- browser console ---", console.map { "#{_1.level} #{_1.message}" } if console.any?
    # Which controllers were running, and where focus and typing were, when it failed.
    state = page.evaluate_script(<<~JS) rescue nil # rubocop:disable Style/RescueModifier
      ({ ready: document.readyState, loaded: document.documentElement.hasAttribute("data-controllers-loaded"),
         controllers: (window.Stimulus?.controllers || []).map((c) => c.identifier),
         focused: document.activeElement?.outerHTML?.slice(0, 200),
         typed: [...document.querySelectorAll("input[type=search], input[type=text]")].map((i) => i.name + "=" + i.value) })
    JS
    puts "--- page state ---", state.inspect
  end

  # Wait until every Stimulus controller has loaded (controllers/index.js marks <html>) before
  # the test types or clicks: on a cold CI browser, input before then was lost, so searches
  # never ran and menus never opened.
  def visit(...)
    super
    assert_selector "html[data-controllers-loaded]", visible: :all, wait: 10
  end
end
