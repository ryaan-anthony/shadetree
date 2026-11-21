require "application_system_test_case"

# JOB-03: moving visits on the team calendar in a real browser: dragged on desktop (then
# undone), and from the quick-edit sheet, with a warning on the way. QA #274: booking a visit at
# a slot and moving one with the keyboard alone.
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
    sign_in_with_form(@owner.email, "password123")
    assert_text "Home"
  end

  def moved = Tenancy.with_business(@business) { Visit.find(@visit.id) }

  test "drag a visit to another day, then undo it" do
    visit admin_schedule_path(date: @monday.iso8601)
    thursday = find("#schedule-grid .cal-day[aria-label='#{(@monday + 3).strftime("%A, %B %-d")}']")
    # A synthetic drag can be dropped by a slow CI Chrome before the drop lands: drag again
    # while the visit hasn't moved (once it has, a repeat drop on Thursday changes nothing).
    page.document.synchronize(20) do
      find("#cal-visit-#{@visit.uid}").drag_to(thursday) if moved.scheduled_on == @monday && page.has_no_text?("Moved: Maria Lopez", wait: 0)
      raise Capybara::ExpectationNotMet, "the drag didn't move the visit" unless page.has_text?("Moved: Maria Lopez", wait: 4)
    end
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

  # What has focus: its text (a slot's is its name), id, value and focus key.
  def focused = evaluate_script("(({ textContent: t, id, value, dataset: d }) => ({ text: t.trim().replace(/\\s+/g, ' '), id, value, key: d.scheduleFocus }))(document.activeElement)").symbolize_keys

  # Keys typed wherever focus is, as a person would (an element's own send_keys can get stuck
  # inside a date field's parts).
  def press(*keys) = page.driver.browser.action.send_keys(*keys).perform

  # Presses Tab until focus is where the block says (a real failure fails after `max` presses).
  def tab_until(max: 150, &done)
    max.times do
      press(:tab)
      return if done.(focused)
    end
    flunk "Tab never reached it; focus ended on #{focused.inspect}"
  end

  def assert_focus(message = nil, &done)
    assert page.document.synchronize(5) { done.(focused) || raise(Capybara::ExpectationNotMet) }, message
  rescue Capybara::ExpectationNotMet
    flunk "#{message || "focus"}: on #{focused.inspect}"
  end

  test "book a visit at a slot, open it and move it, with the keyboard only" do
    next_monday = @monday + 7
    waiting = Tenancy.with_business(@business) { Job.create!(client: Client.find_by!(display_name: "Maria Lopez"), title: "Gutter cleaning") }
    visit admin_schedule_path(date: next_monday.iso8601)
    find("a[aria-label='Next week']").execute_script("this.focus()") # start in the page header, then Tab into the grid
    tab_until { _1[:text].start_with?("New visit, ") }
    assert focused[:text].start_with?("New visit, #{next_monday.strftime("%A, %B %-d")}, 9:00 AM"), "one tab stop into the slots: Monday at 9"

    press(:down, :right)
    assert_focus("arrow keys move between hours and days") { _1[:text].start_with?("New visit, #{(next_monday + 1).strftime("%A, %B %-d")}, 10:00 AM") }
    press(:enter)
    assert_focus("the panel's heading gets focus") { _1[:text] == "New visit" }
    assert_text "#{(next_monday + 1).strftime("%A, %B %-d, %Y")} · 10:00 AM"
    press(:tab, :tab)
    assert_focus { _1[:text] == "Cancel" }
    press(:enter)
    assert_focus("Cancel goes back to the slot") { _1[:text].start_with?("New visit, #{(next_monday + 1).strftime("%A, %B %-d")}, 10:00 AM") }
    assert_no_css "turbo-frame#schedule_visit h2"

    press(:enter)
    assert_focus { _1[:text] == "New visit" }
    press(:tab)
    assert_focus { _1[:id] == "new-visit-job" }
    press(:down) # the first job needing a visit
    assert_equal waiting.uid, find("#new-visit-job").value
    press(:tab, :tab, :enter) # Cancel, Continue
    assert_text "Schedule a visit"
    assert_equal (next_monday + 1).iso8601, find_field("Date (or first day)").value
    assert_equal "10:00", find_field("Start").value
    tab_until { _1[:id] == "visit_duration_hours" }
    press(:enter) # submits the form

    assert_text "Visit scheduled for"
    booked = Tenancy.with_business(@business) { waiting.visits.sole }
    assert_equal [ next_monday + 1, "10:00" ], [ booked.scheduled_on, booked.start_time ]
    assert_focus("back on the calendar, focus is on the new visit") { _1[:key] == booked.uid }
    assert_no_current_path(/focus=/)

    press(:space)
    assert_focus("Space opens the visit; its heading gets focus") { _1[:text] == "Maria Lopez" }
    tab_until { _1[:text] == "Move" }
    press(:enter)
    assert_css "dialog[open]"
    tab_until { _1[:id] == "move-#{booked.uid}-on" }
    press((next_monday + 2).strftime("%m%d%Y"))
    tab_until { _1[:value] == "Move visit" }
    press(:enter)

    assert_text "Moved: Maria Lopez"
    assert_equal next_monday + 2, Tenancy.with_business(@business) { booked.reload.scheduled_on }
    assert_focus("focus is back on the moved visit") { _1[:key] == booked.uid }
  end
end
