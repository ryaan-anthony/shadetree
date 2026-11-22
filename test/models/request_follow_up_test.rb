require "test_helper"

# CLI-07: assigning a request to someone to follow up, moving it, handing it on, taking it off
# them, and what that records and tells people.
class RequestFollowUpTest < ActiveSupport::TestCase
  include PermissionHelpers # member_with_role

  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @tech = member_with_role(:technician)
    @admin = member_with_role(:admin)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @request = ServiceRequest.create!(client: @maria, source: "phone", description: "Fence repair")
    end
  end

  def assign(request = @request, by: @owner, **attrs)
    as_business(@business) do
      defaults = request.follow_up ? {} : { user: @tech, scheduled_on: @business.today }
      RequestFollowUp.assign!(request, defaults.merge(attrs), by:)
    end
  end

  def notices(user) = as_business(@business) { Notification.where(user:).order(:id).map { [ _1.kind, _1.title, _1.path ] } }
  def history = as_business(@business) { @request.events.reload.map { [ _1.kind, _1.data.except("from", "to") ] } }

  test "assigning: today, anytime and a site visit unless said otherwise; a New request moves to In progress" do
    follow_up = assign
    assert_equal [ Date.new(2026, 11, 23), "anytime", "visit", 60, @owner ], [ follow_up.scheduled_on, follow_up.timing, follow_up.kind, follow_up.duration_minutes, follow_up.assigned_by ]
    assert_equal "Mon, Nov 23 · Anytime", follow_up.when_label
    assert_equal "in_progress", as_business(@business) { @request.reload.status }
    assert_equal [ [ "assigned", {} ] ], history
    assert_equal [ [ "request_assigned", "Yours to follow up: site visit for Maria Lopez, Mon, Nov 23 · Anytime", "/admin/my-day" ] ], notices(@tech)

    call = assign(as_business(@business) { ServiceRequest.create!(client: @maria, source: "phone", description: "Quote by phone") },
                  user: @admin, kind: "call", timing: "exact", start_time: "14:00", duration_hours: "")
    assert_equal [ 15, "2 pm", Time.utc(2026, 11, 23, 19, 15) ], [ call.duration_minutes, call.time_label, call.ends_at ], "a call is a quarter of an hour unless said"
    assert_equal "/admin/requests/#{call.service_request.uid}", notices(@admin).last.last, "people who can see requests open the request"
  end

  test "moving, handing on and changing details are each recorded, and the people concerned are told" do
    assign(timing: "exact", start_time: "14:00")
    assign(scheduled_on: Date.new(2026, 11, 24), timing: "window", start_time: "13:00", window_end_time: "15:00")
    assign(user: @admin, instructions: "Bring the ladder")
    assign(user: @admin, kind: "call", instructions: "Ring first")

    kinds = as_business(@business) { @request.events.map(&:kind) }
    assert_equal %w[assigned rescheduled reassigned updated updated], kinds
    reassigned = as_business(@business) { @request.events.find_by(kind: "reassigned") }
    assert_equal [ @tech.id, @admin.id ], reassigned.data.values_at("from_user_id", "to_user_id")
    assert_equal [ %w[instructions], %w[kind instructions] ], as_business(@business) { @request.events.where(kind: "updated").map { _1.data["changed"] } }
    assert_equal [ [ "request_assigned", "Yours to follow up: site visit for Maria Lopez, Mon, Nov 23 · 2 pm" ],
                   [ "request_changed", "Moved: site visit for Maria Lopez is now Tue, Nov 24 · Arrive 1–3 pm" ],
                   [ "request_changed", "No longer yours: site visit for Maria Lopez, Tue, Nov 24 · Arrive 1–3 pm" ] ], notices(@tech).map { _1.first(2) }
    assert_equal [ [ "request_assigned", "Yours to follow up: site visit for Maria Lopez, Tue, Nov 24 · Arrive 1–3 pm" ],
                   [ "request_changed", "Changed: call with Maria Lopez, Tue, Nov 24 · Arrive 1–3 pm" ] ], notices(@admin).map { _1.first(2) }
    assert_empty notices(@owner), "whoever makes the change isn't told"
  end

  test "unassigning, archiving and quoting take it off the assignee; a closed request can't be assigned" do
    assign
    as_business(@business) { @request.reload.follow_up.end!(by: @owner) }
    assert_nil as_business(@business) { @request.reload.follow_up }
    assign
    as_business(@business) { @request.reload.move_to!("archived", by: @admin) }
    assert_equal %w[assigned unassigned assigned ended], history.map(&:first)
    assert_equal "archived", history.last.last["reason"]
    assert_equal [ "No longer yours: site visit for Maria Lopez, Mon, Nov 23 · Anytime", "The request was archived." ],
                 as_business(@business) { Notification.where(user: @tech).order(:id).last.then { [ _1.title, _1.body ] } }
    assert_raises(RequestFollowUp::NotOpen) { assign }

    as_business(@business) { @request.move_to!("in_progress") }
    assign
    as_business(@business) { @request.reload.create_quote!(by: @owner) }
    assert_equal [ "ended", { "reason" => "quoted" } ], history.last
    assert_equal 0, as_business(@business) { RequestFollowUp.count }
  end

  test "only active members of this business can be assigned" do
    error = assert_raises(ActiveRecord::RecordInvalid) { assign(user: users(:two)) }
    assert_match "Only people on your team", error.message
    as_business(@business) { BusinessUser.find_by(user: @admin).update!(active: false, deactivated_at: Time.current) }
    assert_raises(ActiveRecord::RecordInvalid) { assign(user: @admin) }
    assert_raises(ActiveRecord::RecordInvalid) { assign(user: nil) }
  end

  test "warnings: outside the hours, and overlapping the assignee's visits and other follow-ups, both ways" do
    follow_up = as_business(@business) { ServiceRequest.new(client: @maria).build_follow_up(user: @tech, scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "18:00").tap(&:validate) }
    assert_equal [ "That's outside your hours (8 am–5 pm)." ], as_business(@business) { VisitWarnings.for([ follow_up ]) }

    assign(scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "10:00")
    as_business(@business) do
      job = Job.create!(client: @maria, title: "Spring cleanup")
      visit = job.visits.new(scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "09:30", duration_minutes: 90, assignee_ids: [ @tech.id ]).tap(&:validate)
      assert_equal [ "#{@tech.full_name} has a site visit for Maria Lopez then (10 am)." ], VisitWarnings.for([ visit ])
      visit.schedule!(by: @owner)
      other = ServiceRequest.create!(client: @maria, source: "phone", description: "Gutters")
      call = other.build_follow_up(user: @tech, kind: "call", scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "10:30").tap(&:validate)
      assert_equal [ "#{@tech.full_name} is on #{job.number} Spring cleanup then (9:30 am).", "#{@tech.full_name} has a site visit for Maria Lopez then (10 am)." ],
                   VisitWarnings.for([ call ])
      assert_empty VisitWarnings.for([ @request.reload.follow_up ]).grep(/site visit/), "a follow-up doesn't overlap itself"
    end
  end

  test "a booked site visit is on the client's timeline; calls aren't" do
    assign(kind: "call")
    assert_empty as_business(@business) { @maria.events.where(kind: "follow_up_booked") }
    assign(kind: "visit")
    assign(scheduled_on: Date.new(2026, 11, 25))
    assert_equal [ "Mon, Nov 23, 2026 · Anytime" ], as_business(@business) { @maria.events.where(kind: "follow_up_booked").map { _1.data["when"] } },
                 "once, when it's booked as a site visit"
  end

  test "deleting the assignee's account, or erasing the client, takes it off their list" do
    assign
    assert @tech.delete_account!
    assert_nil as_business(@business) { @request.reload.follow_up }
    assign(user: @admin, scheduled_on: @business.today)
    as_business(@business) { ClientErasure.new(@maria, by: @owner).erase! }
    assert_nil as_business(@business) { @request.reload.follow_up }
  end

  test "another business's requests and members can't be used" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Theirs")
    end
    assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { RequestFollowUp.create!(service_request: theirs, user: @tech, scheduled_on: Date.current) } }
    as_business(@business) { assert_empty ServiceRequest.where(id: theirs.id) }
  end
end
