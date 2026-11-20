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
    diag = page.evaluate_script(<<~JS) rescue nil # rubocop:disable Style/RescueModifier
      (() => { const d = window.__diag || {}; const b = [...document.querySelectorAll("button")].find((x) => x.textContent.trim() === "Move");
        const r = b?.getBoundingClientRect(); const at = r && document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
        const pick = document.querySelector("[data-client-picker-target=input]"); const pr = pick?.getBoundingClientRect();
        return { events: d.events, frames: d.frames, hasFocus: document.hasFocus(), vis: document.visibilityState, inner: [innerWidth, innerHeight, devicePixelRatio, scrollY],
          dialogs: [...document.querySelectorAll("dialog")].map((x) => [x.id, x.open, getComputedStyle(x).opacity, getComputedStyle(x).display]),
          move: r && [r.x, r.y, r.width, r.height, at?.outerHTML?.slice(0, 120)], pick: pr && [pr.x, pr.y, pick.value, document.elementFromPoint(pr.x + 5, pr.y + 5)?.outerHTML?.slice(0, 80)],
          anims: document.getAnimations().map((a) => [a.animationName, a.playState, a.currentTime]) } })()
    JS
    puts "--- diag ---", diag.inspect
    puts "--- window ---", page.current_window.size.inspect rescue nil # rubocop:disable Style/RescueModifier
    puts "--- screenshot ---", page.driver.browser.screenshot_as(:base64), "--- end screenshot ---" if ENV["DIAG_SHOT"]
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
    execute_script(<<~JS)
      window.__diag = { events: [], frames: 0 }
      ;["pointerdown", "mousedown", "mouseup", "click", "keydown", "input", "focusin", "focusout", "resize", "scroll"].forEach((t) => window.addEventListener(t, (e) => {
        const el = e.target; window.__diag.events.push(`${(performance.now() / 1000).toFixed(2)} ${t}:${el?.tagName || "win"}:${(el?.textContent || "").trim().slice(0, 12)}`) }, true))
      const tick = () => { window.__diag.frames++; requestAnimationFrame(tick) }; requestAnimationFrame(tick)
    JS
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
      puts "\nDIAG-SIGNIN-CLICK-RAISED in #{name}"
    end
    assert_selector "html[data-controllers-loaded]", visible: :all, wait: 10
  end
end
