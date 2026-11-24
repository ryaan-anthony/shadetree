require "test_helper"

# PLT-17: the calendar's "Color by status" follows the colour map. In progress takes a deeper info
# blue (it was amber); Scheduled keeps its lighter sky tint so the two stay apart; the legend
# names each in the map's words, and a started or finished visit says so in words too.
class Admin::ScheduleStatusColoursTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @monday = Date.new(2026, 11, 23)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      job = Job.create!(client: maria, title: "Spring cleanup")
      book = ->(hour) { job.visits.new(scheduled_on: @monday, timing: "exact", start_time: hour, duration_minutes: 60, assignee_ids: [ @owner.id ]).tap { _1.schedule!(by: @owner, notify_client: false) } }
      @scheduled = book.("08:00")
      @started = book.("10:00").tap { _1.update_columns(status: "in_progress") }
      @done = book.("13:00").tap { _1.update_columns(status: "completed") }
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "by status, each visit's colour and words follow the map, and the legend names them" do
    get admin_schedule_path(date: @monday.iso8601, color: "status")
    assert_select "#cal-visit-#{@scheduled.uid}.cal-status-scheduled"
    assert_select "#cal-visit-#{@started.uid}.cal-status-in-progress", /In progress/
    assert_select "#cal-visit-#{@done.uid}.cal-status-completed", /Completed/
    assert_select "#cal-visit-#{@scheduled.uid}", text: /In progress|Completed/, count: 0
    assert_select "ul[aria-label='Status colors'] li", text: "Scheduled"
    assert_select "ul[aria-label='Status colors'] li", text: "In progress"
    assert_select "ul[aria-label='Status colors'] li", text: "Completed"
  end

  test "In progress is a deeper info blue and Scheduled keeps its sky tint" do
    css = Rails.root.join("app/assets/tailwind/components.css").read
    assert_includes css, ".cal-status-in-progress { background: var(--color-info-300); border-color: var(--color-info-ink); color: var(--color-info-ink); }"
    assert_includes css, ".cal-status-scheduled { background: var(--color-cal-sky);"
    assert_equal :info, StatusHelper::MAP[:visit]["in_progress"].first
  end
end
