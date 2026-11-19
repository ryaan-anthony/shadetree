require "application_system_test_case"

# CLI-03 in a browser at phone width, with CSRF protection on as in production.
class PublicRequestSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(request_form_enabled: true)
    as_business(@business) { CatalogItem.create!(name: "Weekly mowing", unit: "visit", show_on_request_form: true) }
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    page.current_window.resize_to(360, 740)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery_protection
    page.current_window.resize_to(1400, 1400) # the browser is shared: later tests expect desktop width
  end

  test "someone asks for a quote from their phone" do
    visit public_request_path(@business.handle)
    check "Weekly mowing"
    choose "I'm flexible"
    fill_in "Your name", with: "Hannah Brooks"
    fill_in "Phone", with: "555 010 0444"
    fill_in "Street address", with: "5 Pine Rd"
    sleep AbuseProtection::MIN_SECONDS # people take longer than this; the form expects it
    click_on "Send request"
    assert_text "Request sent"
    request = as_business(@business) { ServiceRequest.sole }
    assert_equal [ "Weekly mowing" ], request.service_names
  end
end
