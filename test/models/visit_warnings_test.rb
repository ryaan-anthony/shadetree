require "test_helper"

# JOB-02: warnings before booking (hours, closures, double-booking), several days at once, and
# telling the people going.
class VisitWarningsTest < ActiveSupport::TestCase
  include PermissionHelpers # member_with_role
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @tech = member_with_role(:technician)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: maria, title: "Spring cleanup")
      other_client = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5550100101" } ])
      @other_job = Job.create!(client: other_client, title: "Gutter cleaning")
    end
  end

  def build(job = @job, **attrs)
    as_business(@business) do
      job.visits.new({ scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "09:00", duration_minutes: 120, assignee_ids: [ @tech.id ] }.merge(attrs)).tap(&:validate)
    end
  end

  def warnings(*visits) = as_business(@business) { VisitWarnings.for(visits) }

  test "a visit inside the hours, on an open day, with nobody double-booked, has no warnings" do
    assert_empty warnings(build)
  end

  test "outside the hours, on a closed day, and on a closure" do
    assert_equal [ "That's outside your hours (8 am–5 pm)." ], warnings(build(start_time: "16:00"))
    assert_equal [ "That's outside your hours (8 am–5 pm)." ], warnings(build(timing: "window", start_time: "13:00", window_end_time: "15:00", duration_minutes: 180)),
                 "the latest arrival plus the duration runs past closing"
    assert_equal [ "You're closed on Saturdays." ], warnings(build(scheduled_on: Date.new(2026, 11, 28), timing: "anytime"))
    as_business(@business) do
      Closure.create!(reason: "Thanksgiving", starts_on: Date.new(2026, 11, 26))
      Closure.create!(reason: "the staff lunch", starts_on: Date.new(2026, 11, 24), part_of_day: true, start_time: "12:00", end_time: "13:00")
    end
    assert_equal [ "You're closed for Thanksgiving." ], warnings(build(scheduled_on: Date.new(2026, 11, 26), timing: "anytime"))
    assert_equal [ "You're closed 12 pm–1 pm for the staff lunch." ], warnings(build(start_time: "11:30"))
    assert_empty warnings(build(start_time: "13:00"))
    @business.update!(weekly_hours: nil)
    assert_empty warnings(build(start_time: "22:00")), "no hours set, no hours warnings"
  end

  test "someone going is already on another visit then" do
    as_business(@business) { @other_job.visits.new(scheduled_on: Date.new(2026, 11, 24), timing: "window", start_time: "10:00", window_end_time: "11:00", duration_minutes: 60, assignee_ids: [ @tech.id ]).schedule!(by: @owner) }
    assert_equal [ "#{@tech.full_name} is on #{@other_job.number} Gutter cleaning then (10–11 am)." ], warnings(build)
    assert_empty warnings(build(start_time: "13:00")), "after the other visit ends (11 am + 1 h)"
    assert_empty warnings(build(assignee_ids: [ @owner.id ]))
    assert_empty warnings(build(timing: "anytime")), "an anytime visit doesn't overlap"
  end

  test "several days: one visit per day, skipping closed days if asked, in one go" do
    hours = OpeningHours.new(@business)
    assert_equal [ Date.new(2026, 11, 26), Date.new(2026, 11, 27), Date.new(2026, 11, 30) ],
                 Visit.plan_dates("2026-11-26", through: "2026-11-30", skip_closed: true, hours:), "Thu, Fri, then Mon"
    assert_equal [ Date.new(2026, 11, 26), Date.new(2026, 11, 27), Date.new(2026, 12, 3) ],
                 Visit.plan_dates("2026-11-26", extra: [ "2026-12-03", "", "2026-11-27", "nonsense" ])
    assert_equal Visit::MAX_DAYS + 1, Visit.plan_dates("2026-01-01", through: "2026-12-31").size

    visits = Visit.plan_dates("2026-11-24", through: "2026-11-26").map { build(scheduled_on: _1) }
    as_business(@business) { Visit.schedule_all!(visits, by: @owner) }
    assert_equal 3, as_business(@business) { @job.visits.count }
    assert_equal [ "You're on Spring cleanup (#{@job.number}): 3 visits, Nov 24 to Nov 26" ], as_business(@business) { Notification.where(user: @tech).pluck(:title) }
    several = warnings(build(scheduled_on: Date.new(2026, 11, 28), timing: "anytime"), build(scheduled_on: Date.new(2026, 11, 29), timing: "anytime"))
    assert_equal [ "Sat, Nov 28: You're closed on Saturdays.", "Sun, Nov 29: You're closed on Sundays." ], several
  end

  test "the people going hear about visits they're put on, moved, taken off or cancelled" do
    visit = build.tap { |v| as_business(@business) { v.schedule!(by: @owner) } }
    admin = member_with_role(:admin)
    as_business(@business) do
      visit.reschedule!({ scheduled_on: Date.new(2026, 11, 25), assignee_ids: [ @tech.id, admin.id ] }, by: @owner)
      visit.reschedule!({ assignee_ids: [ admin.id ] }, by: @owner)
      visit.cancel!(by: admin, reason: "Rain")
    end
    titles = ->(user) { as_business(@business) { Notification.where(user:).order(:id).map { [ _1.kind, _1.title, _1.path ] } } }
    job_path = "/admin/jobs/#{@job.uid}"
    assert_equal [ [ "visit_assigned", "You're on Spring cleanup (#{@job.number}): Tue, Nov 24 · 9 am", "/admin" ],
                   [ "visit_changed", "Moved: Spring cleanup (#{@job.number}) is now Wed, Nov 25 · 9 am", "/admin" ],
                   [ "visit_changed", "You're no longer on Spring cleanup (#{@job.number}) on Wed, Nov 25, 2026 · 9 am", "/admin" ] ], titles.(@tech)
    assert_equal [ [ "visit_assigned", "You're on Spring cleanup (#{@job.number}): Wed, Nov 25 · 9 am", job_path ] ], titles.(admin),
                 "an admin opens the job; the one who cancelled isn't told"
    assert_empty titles.(@owner), "the person making changes isn't notified"
  end
end
