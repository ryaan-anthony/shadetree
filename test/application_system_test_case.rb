require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

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
  end

  # Wait until every Stimulus controller has loaded (controllers/index.js marks <html>) before
  # the test types or clicks: on a cold CI browser, input before then was lost, so searches
  # never ran and menus never opened.
  def visit(...)
    super
    assert_selector "html[data-controllers-loaded]", visible: :all, wait: 10
  end
end
