require "test_helper"

# Chrome 157 sometimes reports an element replaced by a Turbo render as "Node with given id does
# not belong to the document" (an UnknownError) instead of a stale element. Capybara retries
# stale elements until its wait time runs out, but not unknown errors, so treat this one as stale.
module StaleNodeAsStaleElement
  def error
    ex = super
    return ex unless ex.is_a?(Selenium::WebDriver::Error::UnknownError) && ex.message.include?("does not belong to the document")

    begin
      raise Selenium::WebDriver::Error::StaleElementReferenceError, ex.message, cause: ex.cause # keeps the remote trace
    rescue Selenium::WebDriver::Error::StaleElementReferenceError => stale
      stale
    end
  end
end
Selenium::WebDriver::Remote::Response.prepend(StaleNodeAsStaleElement)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_option("goog:loggingPrefs", { browser: "ALL" }) # so a failure can show the console
  end

  # Icon-only buttons are named with aria-label; let click_on and assert_button find them.
  Capybara.enable_aria_label = true

  # When a test fails, show what the server did meanwhile (requests, status, timing) and the
  # browser's console, so a CI-only failure can be diagnosed from the log. This runs in
  # before_teardown: Rails resets the browser to a blank page before teardown blocks run, so
  # the page state must be read here, while the failing page is still open.
  def before_teardown
    print_failure_diagnostics if failed? && Capybara::Session.instance_created? # no browser, nothing to show
  ensure
    super
  end

  def print_failure_diagnostics
    log = Rails.root.join("log/test.log")
    lines = File.exist?(log) ? File.readlines(log).last(400).grep(/Started|Completed|Error|Processing by/).last(40) : []
    puts "\n--- server requests before the failure ---", lines.join
    console = page.driver.browser.respond_to?(:logs) ? (page.driver.browser.logs.get(:browser) rescue []) : [] # rubocop:disable Style/RescueModifier
    puts "--- browser console ---", console.map { "#{_1.level} #{_1.message}" } if console.any?
    # Which controllers were running, and where focus and typing were, when it failed.
    state = page.evaluate_script(<<~JS) rescue nil # rubocop:disable Style/RescueModifier
      ({ url: location.pathname, ready: document.readyState, loaded: document.documentElement.hasAttribute("data-controllers-loaded"),
         failed: document.documentElement.dataset.controllersFailed,
         controllers: (window.Stimulus?.controllers || []).map((c) => c.identifier),
         focused: document.activeElement?.outerHTML?.slice(0, 200),
         typed: [...document.querySelectorAll("input[type=search], input[type=text], input[type=tel], input[type=email]")].map((i) => i.name + "=" + i.value) })
    JS
    puts "--- page state ---", state.inspect
  rescue StandardError => e
    puts "--- diagnostics failed: #{e.class}: #{e.message}"
  end

  # Wait until every Stimulus controller has loaded (controllers/index.js marks <html>) before
  # the test types or clicks: on a cold CI browser, input before then was lost, so searches
  # never ran and menus never opened.
  def visit(...)
    super
    assert_selector "html[data-controllers-loaded]", visible: :all, wait: 10
    failed = page.evaluate_script("document.documentElement.dataset.controllersFailed")
    flunk "Controllers failed to load: #{failed}" if failed # fail here, at the cause, not on a later assertion
  end

  # Signs in through the form. Signing in loads the next page in full (no Turbo: a new session
  # brings a new CSP nonce, PLT-13); ChromeDriver can report the click as failing because the
  # page it clicked on is already gone, which is fine here.
  def sign_in_with_form(email, password = "password123")
    fill_in "Email", with: email
    fill_in "Password", with: password
    begin
      click_button "Sign in" # the navigation has a "Sign in" link too (MKT-01)
    rescue Selenium::WebDriver::Error::UnknownError => error
      raise unless error.message.include?("does not belong to the document")
    end
    assert_selector "html[data-controllers-loaded]", visible: :all, wait: 10
  end
end
