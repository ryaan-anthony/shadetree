require "test_helper"

# JOB-02: visits on a job: when they are, who's going, what changed, and the job's status.
class VisitTest < ActiveSupport::TestCase
  include PermissionHelpers # member_with_role

  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    @tech = member_with_role(:technician)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: maria, title: "Spring cleanup")
    end
  end

  def visit(**attrs)
    as_business(@business) do
      @job.visits.new({ scheduled_on: Date.new(2026, 11, 24), timing: "window", start_time: "08:00", window_end_time: "10:00", duration_minutes: 120 }.merge(attrs))
          .schedule!(by: @owner)
    end
  end

  test "a window, a start time, or anytime, on the visit's date in the business's zone" do
    window = visit
    assert_equal [ Time.utc(2026, 11, 24, 13), Time.utc(2026, 11, 24, 15) ], [ window.starts_at, window.window_ends_at ]
    assert_equal "Arrive 8–10 am", window.time_label
    assert_equal Time.utc(2026, 11, 24, 17), window.ends_at, "the window's end plus the duration"
    exact = visit(timing: "exact", start_time: "13:30", window_end_time: "15:00")
    assert_equal [ "1:30 pm", nil ], [ exact.time_label, exact.window_ends_at ]
    anytime = visit(timing: "anytime", start_time: "09:00")
    assert_equal [ "Anytime", nil, nil ], [ anytime.time_label, anytime.starts_at, anytime.ends_at ]
    assert_equal "Arrive 11 am–1 pm", visit(start_time: "11:00", window_end_time: "13:00").time_label
  end

  test "times keep to the local clock across DST, and moving the date keeps the time" do
    before = visit(scheduled_on: Date.new(2026, 3, 6), timing: "exact", start_time: "09:00")
    assert_equal Time.utc(2026, 3, 6, 14), before.starts_at
    as_business(@business) { before.reschedule!({ scheduled_on: Date.new(2026, 3, 9) }, by: @owner) }
    assert_equal Time.utc(2026, 3, 9, 13), before.starts_at, "still 9 am, now EDT"
    assert_equal "09:00", before.start_time
  end

  test "times and durations are checked" do
    as_business(@business) do
      assert_includes @job.visits.new(scheduled_on: Date.new(2026, 11, 24), timing: "window", start_time: "10:00", window_end_time: "09:00").tap(&:validate)
                          .errors.full_messages, "Window end time must be after the window starts"
      assert_not @job.visits.new(scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "9am").valid?
      assert_not @job.visits.new(scheduled_on: Date.new(2026, 11, 24), timing: "anytime", duration_hours: "30").valid?
      assert_equal 90, @job.visits.new(duration_hours: "1.5").duration_minutes
      outsider = User.create!(email: "x@example.com", password: "password123", confirmed_at: Time.current)
      assert_includes @job.visits.new(scheduled_on: Date.new(2026, 11, 24), assignee_ids: [ outsider.id ]).tap(&:validate).errors.full_messages,
                      "Assignee ids must be members of your team"
    end
  end

  test "changes are recorded with who and what" do
    v = visit(assignee_ids: [ @owner.id ])
    as_business(@business) do
      v.reschedule!({ scheduled_on: Date.new(2026, 11, 25), assignee_ids: [ @tech.id ] }, by: @owner)
      v.cancel!(by: @owner, reason: "Rain")
      v.restore!(by: @owner)
      assert_equal %w[scheduled rescheduled reassigned cancelled restored], v.events.map(&:kind)
      moved = v.events.find_by!(kind: "rescheduled")
      assert_equal [ "Tue, Nov 24 · Arrive 8–10 am", "Wed, Nov 25 · Arrive 8–10 am" ], [ moved.data["from"], moved.data["to"] ]
      assert_equal [ [ @tech.full_name ], [ @owner.full_name ] ], v.events.find_by!(kind: "reassigned").data.values_at("added", "removed")
      assert_equal [ @tech ], v.assignees.to_a
    end
  end

  test "the job's status follows its visits" do
    assert_equal "unscheduled", @job.reload.status
    first = visit
    assert_equal "scheduled", @job.reload.status
    second = visit(scheduled_on: Date.new(2026, 11, 25))
    as_business(@business) { first.complete!(by: @owner) }
    assert_equal "in_progress", @job.reload.status, "work done, more to come"
    as_business(@business) { second.cancel!(by: @owner) }
    assert_equal "in_progress", @job.reload.status, "work done, nothing more booked: staff complete it"
    as_business(@business) { first.update_columns(status: "cancelled") && @job.refresh_status! }
    assert_equal "unscheduled", @job.reload.status
  end

  test "completing a job finishes its visits; cancelling cancels them; finished jobs take no new visits" do
    under_way = visit.tap { _1.update_columns(status: "in_progress") }
    later = visit(scheduled_on: Date.new(2026, 12, 1))
    as_business(@business) { @job.reload.complete!(by: @owner) }
    assert_equal [ "completed", "cancelled" ], [ under_way.reload.status, later.reload.status ]
    assert_equal "Job completed", later.cancel_reason
    as_business(@business) do
      assert_raises(Visit::NotOpen) { later.restore!(by: @owner) }
      @job.reopen!
      later.restore!(by: @owner)
      assert_equal "in_progress", @job.reload.status, "one visit done, one to come"
      @job.cancel!(by: @owner, reason: "Moved")
      assert_equal "cancelled", later.reload.status
    end
  end

  test "the suggested duration comes from the job's services, then the industry, then an hour" do
    as_business(@business) do
      assert_equal 60, @job.suggested_visit_minutes
      item = CatalogItem.create!(name: "Mowing", unit: "each", unit_price: "40", duration_minutes: 45)
      @job.line_items.create!(name: "Mowing", catalog_item: item, quantity: 2, unit_price: "40")
      assert_equal 90, @job.reload.suggested_visit_minutes
    end
  end

  test "visits belong to one business" do
    visit
    assert_equal 0, as_business(businesses(:two)) { Visit.count }
  end
end
