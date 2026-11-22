require "test_helper"

# JOB-08: request follow-ups as Busy for people who schedule but can't see requests.
class ScheduleViewBusyTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 11, 23, 14) # Monday, 9 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    Current.business = @business
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "technician")
    @monday = Date.new(2026, 11, 23)
    client = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5125550101" } ])
    @site = ServiceRequest.create!(client:, source: "phone", description: "Fence")
    RequestFollowUp.assign!(@site, { user: @tech, scheduled_on: @monday, timing: "exact", start_time: "14:00", instructions: "Gate code 4411" }, by: @owner)
    @call = ServiceRequest.create!(client:, source: "phone", description: "Hedges")
    RequestFollowUp.assign!(@call, { user: @owner, kind: "call", scheduled_on: @monday + 1 }, by: @owner)
  end

  teardown { Current.reset }

  def view(**) = ScheduleView.new(@business, date: @monday, follow_ups: :busy, **)

  test "others' follow-ups are Busy, with their time and person and nothing of the request; done ones too" do
    @site.follow_up.done!(by: @tech)
    busy = view.items
    assert_equal [ ScheduleView::Busy ] * 2, busy.map(&:class)
    first = busy.first
    assert_equal [ @tech, @monday, "2 pm", 60 ], [ first.user, first.scheduled_on, first.time_label, first.duration_minutes ]
    %i[service_request client kind done? instructions uid id summary location].each { assert_not first.respond_to?(_1), "Busy has no #{_1}" }
    assert_equal [ first ], view.placed_in(ScheduleView::Column.new(@monday, nil)).map(&:visit)
    assert_equal [ busy.last ], view.anytime_in(ScheduleView::Column.new(@monday + 1, nil))
  end

  test "the viewer's own follow-ups stay follow-ups" do
    items = view(viewer: @tech).items
    assert_equal [ RequestFollowUp, ScheduleView::Busy ], items.map(&:class)
    assert_equal @site.follow_up, items.first
    assert items.first.service_request.association(:client).loaded?, "its client, loaded with it"
  end

  test "people who see requests, and people who see nothing of them, are as before" do
    assert_equal [ RequestFollowUp ] * 2, ScheduleView.new(@business, date: @monday, follow_ups: true).items.map(&:class)
    assert_empty ScheduleView.new(@business, date: @monday, follow_ups: false).items
  end

  test "screen readers hear its time: a start to its end, a window's arrival, or anytime" do
    assert_equal "2 to 3 pm", view.items.first.spoken_time
    assert_equal "anytime", view.items.last.spoken_time
    RequestFollowUp.assign!(@site, { timing: "window", start_time: "11:30", window_end_time: "13:00" }, by: @owner)
    assert_equal "arriving 11:30 am to 1 pm", view.items.first.spoken_time
    RequestFollowUp.assign!(@site, { timing: "exact", start_time: "23:00" }, by: @owner)
    assert_equal "11 pm to 12 am", view.items.first.spoken_time
  end

  test "booked hours count Busy time, as the office's do" do
    assert_equal ScheduleView.new(@business, date: @monday, follow_ups: true).booked_hours, view.booked_hours
    assert_equal 1.0, view.booked_hours[@tech.id]
  end

  test "colored by its person, or neutral by status (done or not)" do
    @site.follow_up.done!(by: @tech)
    busy = view.items.first
    assert_equal view.color_for(@tech), view.visit_color(busy)
    assert_equal "neutral", view(color_by: "status").visit_color(busy)
  end

  test "an empty week's next item can be Busy, with no detail; the viewer's own is theirs" do
    following = ScheduleView.new(@business, date: @monday - 7, follow_ups: :busy).next_item_after
    assert_instance_of ScheduleView::Busy, following
    assert_equal @monday, following.scheduled_on
    assert_equal @site.follow_up, ScheduleView.new(@business, date: @monday - 7, follow_ups: :busy, viewer: @tech).next_item_after
  end

  test "the person and location filters apply to Busy too" do
    assert_equal [ @monday + 1 ], view(member: @owner.id).items.map(&:scheduled_on)
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    north = Location.create!(name: "North yard")
    @call.update!(location: north)
    assert_equal [ @monday + 1 ], view(location: north).items.map(&:scheduled_on)
  end
end
