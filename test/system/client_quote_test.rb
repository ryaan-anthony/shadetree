require "application_system_test_case"

# QTE-03/QTE-05 in a real browser: the client page's own forms (the browser sends an Origin
# header that Rails checks, which integration tests don't), and approving from a phone.
class ClientQuoteSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client: maria).tap do
        _1.title = "Spring cleanup"
        _1.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180", "taxable" => "0" } ])
        _1.save!
        _1.mark_sent!(by: users(:one), channel: "link")
      end
    end
    @link = as_business(@business) { @quote.client_link! }
    # The test environment turns CSRF protection off; these pages' forms must pass it as in
    # production (including the Origin check that a no-referrer policy breaks).
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery_protection
    page.current_window.resize_to(1400, 1400) # the browser is shared: later tests expect desktop width
  end

  test "a client approves the quote from their phone" do
    page.current_window.resize_to(360, 740)
    visit client_link_path(@link.token)
    click_on "Approve quote"
    within("#quote-approve") do
      fill_in "Type your full name to sign", with: "Maria Lopez"
      check "I agree to the quote and its terms."
      click_on "Approve quote"
    end
    assert_text "Thanks, Maria Lopez. You're all set."
    assert_equal "approved", as_business(@business) { @quote.reload.status }
  end

  test "a client asks for changes" do
    visit client_link_path(@link.token)
    click_on "Ask for changes"
    within("#quote-request-changes") do
      fill_in "Your changes", with: "Can you skip the side yard?"
      click_on "Send to #{@business.name}"
    end
    assert_text "You asked for changes."
    assert_equal "changes_requested", as_business(@business) { @quote.reload.status }
  end
end
