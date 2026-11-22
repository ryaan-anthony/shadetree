require "application_system_test_case"

# JOB-08: Busy blocks in a real browser, for someone who schedules but can't see requests: a click
# on one is a click on the hour under it, and a visit dropped on one lands there (with the warning).
class ScheduleBusyTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5,
                      plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @monday = @business.today.beginning_of_week + 7 # next week: every hour can be booked
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @visit = Job.create!(client:, title: "Spring cleanup").visits.new(scheduled_on: @monday, timing: "exact", start_time: "09:00", duration_minutes: 60, assignee_ids: [ @owner.id ])
      @visit.schedule!(by: @owner)
      request = ServiceRequest.create!(client: Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5550100101" } ]), source: "phone", description: "Fence")
      RequestFollowUp.assign!(request, { user: @owner, scheduled_on: @monday, timing: "exact", start_time: "14:00" }, by: @owner)
      dispatcher = Role.create!(name: "Dispatcher", permissions: %w[schedule])
      dee = User.create!(email: "dee@example.com", password: "password123", first_name: "Dee", confirmed_at: Time.current)
      BusinessUser.create!(user: dee, business: @business, role: "custom", role_id: dispatcher.id)
    end
    visit new_user_session_path
    sign_in_with_form("dee@example.com", "password123")
    assert_text "Schedule"
  end

  def moved = Tenancy.with_business(@business) { Visit.find(@visit.id) }

  test "a click on Busy time is a click on that hour: a new visit then" do
    visit admin_schedule_path(date: @monday.iso8601, view: "day")
    busy = find("#schedule-grid .cal-busy", text: "Busy")
    assert_no_text "Sam Ortiz"
    page.document.synchronize(15) do # a click before the page's script connects opens nothing: click again
      page.driver.browser.action.move_to(busy.native).click.perform unless page.has_css?("turbo-frame#schedule_visit", text: "2:00 PM", wait: 0)
      raise Capybara::ExpectationNotMet, "the slot under Busy didn't open" unless page.has_css?("turbo-frame#schedule_visit", text: "2:00 PM", wait: 3)
    end
  end

  test "a visit dropped on Busy time lands there, after the warning that names nobody" do
    visit admin_schedule_path(date: @monday.iso8601)
    busy = find("#schedule-grid .cal-busy", text: "Busy")
    # As for visits: drag again while a slow Chrome dropped it, but never while the warning is up.
    page.document.synchronize(20) do
      find("#cal-visit-#{@visit.uid}").drag_to(busy) unless page.has_css?("dialog[open]", wait: 0)
      raise Capybara::ExpectationNotMet, "the drop didn't reach the hour" unless page.has_css?("dialog[open]", text: "has a request follow-up then", wait: 4)
    end
    within("dialog[open]") do
      assert_text "John Doe has a request follow-up then (2 pm)."
      click_on "Move anyway"
    end
    assert_text "Moved: Maria Lopez", wait: 10
    assert_equal "2 pm", Tenancy.with_business(@business) { moved.time_label }
  end
end
