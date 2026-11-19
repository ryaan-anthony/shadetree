require "application_system_test_case"

# JOB-03: moving visits on the team calendar in a real browser: dragged on desktop (then
# undone), and from the quick-edit sheet, with a warning on the way.
class ScheduleTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @monday = @business.today.beginning_of_week
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @visit = Job.create!(client:, title: "Spring cleanup").visits.new(scheduled_on: @monday, timing: "exact", start_time: "09:00", duration_minutes: 60, assignee_ids: [ @owner.id ])
      @visit.schedule!(by: @owner)
    end
    visit new_user_session_path
    fill_in "Email", with: @owner.email
    fill_in "Password", with: "password123"
    click_on "Sign in"
    assert_text "Home"
  end

  def moved = Tenancy.with_business(@business) { Visit.find(@visit.id) }

  test "drag a visit to another day, then undo it" do
    visit admin_schedule_path(date: @monday.iso8601)
    thursday = find("#schedule-grid .cal-day[aria-label='#{(@monday + 3).strftime("%A, %B %-d")}']")
    find("#cal-visit-#{@visit.uid}").drag_to(thursday)
    assert_text "Moved: Maria Lopez"
    assert_equal @monday + 3, moved.scheduled_on
    within("#flash") { click_on "Undo" }
    assert_text "Put back: Maria Lopez"
    assert_equal @monday, moved.scheduled_on
  end

  test "move a visit from the quick-edit sheet, past a warning" do
    visit admin_schedule_visit_path(@visit)
    # A click that lands before the page's script has connected opens nothing: click again
    # until the dialog is open (a real failure still fails, after 15 seconds).
    page.document.synchronize(15) do
      click_on "Move" unless page.has_css?("dialog[open]", wait: 0)
      raise Capybara::ExpectationNotMet, "the Move dialog didn't open" unless page.has_css?("dialog[open]", wait: 3)
    end
    within("dialog[open]") do
      fill_in "Day", with: @monday + 6
      click_on "Move visit"
    end
    within("dialog[open]") do
      assert_text "You're closed on Sundays."
      click_on "Move anyway"
    end
    assert_text "Moved: Maria Lopez"
    assert_equal @monday + 6, moved.scheduled_on
  end
end
