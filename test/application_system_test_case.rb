require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # Icon-only buttons are named with aria-label; let click_on and assert_button find them.
  Capybara.enable_aria_label = true
end
