require "application_system_test_case"

# CLI-07: assigning a request with the keyboard alone (axe: test/system/accessibility_test.rb).
class RequestFollowUpsTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    # Open every day, 7 am to 9 pm, so today's follow-up has no warning whenever this runs.
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::DAYS.to_h { [ _1.to_s, { "opens" => "07:00", "closes" => "21:00" } ] })
    @owner = users(:one)
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @request_record = ServiceRequest.create!(client:, source: "phone", description: "Fence repair")
    end
    visit new_user_session_path
    sign_in_with_form(@owner.email, "password123")
    assert_text "Home"
  end

  # Keys typed wherever focus is, as a person would.
  def press(*keys) = page.driver.browser.action.send_keys(*keys).perform

  test "assign a request as a call, with the keyboard only" do
    visit admin_service_request_path(@request_record)
    find("#follow-up a", text: "Assign").send_keys(:enter)
    assert_selector "h1", text: "Assign this request"
    find_field("Who follows it up").send_keys(:tab) # the only member is already chosen
    press(:right) # How: Site visit → Call
    assert_predicate find("#follow-up-kind-call"), :checked?
    find("#timing-anytime").send_keys(:left) # Time: Anytime → A start time
    assert_selector "#request_follow_up_start_time", visible: true
    find_field("Instructions for them").send_keys("Ask about the side gate")
    find("input[type=submit][value=Assign]").send_keys(:enter)
    assert_text "John Doe has it: call"
    assert_selector "#follow-up", text: /Call, .* · 9 am/
    assert_equal "Ask about the side gate", Tenancy.with_business(@business) { @request_record.reload.follow_up.instructions }
  end
end
