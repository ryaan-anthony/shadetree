require "application_system_test_case"

# JOB-07: moving a request follow-up on the calendar in a real browser: dragged (then undone),
# and from its quick-edit sheet past a warning.
class ScheduleFollowUpsTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @monday = @business.today.beginning_of_week
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5125550101" } ])
      @request_record = ServiceRequest.create!(client:, source: "phone", description: "Fence")
      RequestFollowUp.assign!(@request_record, { user: @owner, scheduled_on: @monday, timing: "exact", start_time: "09:00" }, by: @owner)
    end
    visit new_user_session_path
    sign_in_with_form(@owner.email, "password123")
    assert_text "Home"
  end

  def moved = Tenancy.with_business(@business) { @request_record.reload.follow_up }

  test "drag a follow-up to another day, then undo it" do
    visit admin_schedule_path(date: @monday.iso8601)
    thursday = find("#schedule-grid .cal-day[aria-label='#{(@monday + 3).strftime("%A, %B %-d")}']")
    page.document.synchronize(20) do # as for visits: drag again while a slow Chrome dropped it
      find("#cal-request-#{@request_record.uid}").drag_to(thursday) if moved.scheduled_on == @monday && page.has_no_text?("Moved: Site visit", wait: 0)
      raise Capybara::ExpectationNotMet, "the drag didn't move the follow-up" unless page.has_text?("Moved: Site visit", wait: 4)
    end
    assert_equal @monday + 3, moved.scheduled_on
    within("#flash") { click_on "Undo" }
    assert_text "Put back: Site visit"
    assert_equal @monday, moved.scheduled_on
  end

  test "move a follow-up from the quick-edit sheet, past a warning" do
    visit admin_schedule_follow_up_path(@request_record)
    page.document.synchronize(15) do
      click_on "Move" unless page.has_css?("dialog[open]", wait: 0)
      raise Capybara::ExpectationNotMet, "the Move dialog didn't open" unless page.has_css?("dialog[open]", wait: 3)
    end
    within("dialog[open]") do
      fill_in "Day", with: @monday + 6
      click_on "Move follow-up"
    end
    within("dialog[open]") do
      assert_text "You're closed on Sundays."
      click_on "Move anyway"
    end
    assert_text "Moved: Site visit for Sam Ortiz"
    assert_equal @monday + 6, moved.scheduled_on
  end
end
