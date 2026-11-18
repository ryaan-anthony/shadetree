require "test_helper"

# JOB-03: what moving a visit on the calendar changes.
class VisitMoveTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    Current.business = @business
    client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
    @job = Job.create!(client:, title: "Spring cleanup")
    @owner = users(:one)
    @monday = Date.new(2026, 11, 23)
  end

  teardown { Current.reset }

  def book(**fields) = @job.visits.new(scheduled_on: @monday, duration_minutes: 60, **fields).tap { _1.schedule!(by: @owner) }

  test "a new day keeps the clock time; a new time moves a window whole" do
    visit = book(timing: "window", start_time: "09:00", window_end_time: "11:00")
    assert_equal({ scheduled_on: @monday + 1, start_time: "09:00", window_end_time: "11:00" }, visit.move_attributes(on: @monday + 1))
    assert_equal({ scheduled_on: @monday, start_time: "14:15", window_end_time: "16:15" }, visit.move_attributes(on: @monday, at: "14:15"))
    assert_raises(ArgumentError) { visit.move_attributes(on: @monday, at: "22:30") }
    assert_raises(ArgumentError) { visit.move_attributes(on: @monday, at: "2pm") }
  end

  test "an anytime visit has no time to move" do
    visit = book(timing: "anytime")
    assert_equal({ scheduled_on: @monday + 2, start_time: nil, window_end_time: nil }, visit.move_attributes(on: @monday + 2, at: "10:00"))
  end

  test "from one person to another, to nobody, or the whole crew" do
    tech = User.create!(email: "t@example.com", password: "password123", first_name: "Tia", confirmed_at: Time.current)
    visit = book(timing: "exact", start_time: "09:00", assignee_ids: [ @owner.id ])
    assert_equal [ tech.id ], visit.move_attributes(on: @monday, from: @owner.id, to: tech.id)[:assignee_ids]
    assert_equal [], visit.move_attributes(on: @monday, from: @owner.id, to: nil)[:assignee_ids]
    assert_equal [ @owner.id, tech.id ], visit.move_attributes(on: @monday, from: nil, to: tech.id)[:assignee_ids]
    assert_not visit.move_attributes(on: @monday, from: @owner.id, to: @owner.id).key?(:assignee_ids), "the same person: no crew change"
    assert_equal [ tech.id ], visit.move_attributes(on: @monday, crew: [ tech.id.to_s ])[:assignee_ids]
  end

  test "a reload forgets times and crew given but not saved" do
    visit = book(timing: "exact", start_time: "09:00")
    visit.assign_attributes(start_time: "15:00", assignee_ids: [ @owner.id ])
    visit.reload
    assert_equal [ "09:00", [] ], [ visit.start_time, visit.assignee_ids ]
  end
end
