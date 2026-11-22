require "test_helper"

# CLI-07: assigning a request to someone to follow up, moving it, handing it on, taking it off
# them, and what that records and tells people.
class RequestFollowUpTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    @owner = users(:one)
    @pat = member("Pat", :admin)
    @sam = member("Sam", :admin)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @request = ServiceRequest.create!(client: @maria, source: "phone", description: "Fence repair")
    end
  end

  def member(name, role, business: @business)
    User.create!(email: "#{name.downcase}-#{SecureRandom.hex(3)}@example.com", password: "password123", first_name: name, confirmed_at: Time.current)
        .tap { BusinessUser.create!(user: _1, business:, role: role.to_s) }
  end

  def assign(request = @request, by: @owner, **attrs)
    as_business(@business) do
      defaults = request.reload.follow_up ? {} : { user: @pat, scheduled_on: @business.today }
      RequestFollowUp.assign!(request, defaults.merge(attrs), by:)
    end
  end

  def follow_up = as_business(@business) { @request.reload.follow_up }
  def notices(user) = as_business(@business) { Notification.where(user:).order(:id).map { [ _1.kind, _1.title, _1.body ] } }
  def history = as_business(@business) { @request.events.reload.map { [ _1.kind, _1.data["reason"] ] } }

  test "assigning: today, anytime and a site visit unless said otherwise; a New request moves to In progress" do
    assign
    assert_equal [ Date.new(2026, 11, 23), "anytime", "visit", 60, @owner ], [ follow_up.scheduled_on, follow_up.timing, follow_up.kind, follow_up.duration_minutes, follow_up.assigned_by ]
    assert_equal "in_progress", as_business(@business) { @request.reload.status }
    assert_equal [ [ "assigned", nil ] ], history
    assert_equal [ "request_assigned", "Yours to follow up: site visit for Maria Lopez, Mon, Nov 23 · Anytime" ], notices(@pat).first.first(2)
    assert_equal "/admin/requests/#{@request.uid}", as_business(@business) { Notification.find_by(user: @pat).path }

    call = assign(as_business(@business) { ServiceRequest.create!(client: @maria, source: "phone", description: "Quote by phone") },
                  kind: "call", timing: "exact", start_time: "14:00", duration_minutes: nil)
    assert_equal [ 15, "2 pm", Time.utc(2026, 11, 23, 19, 15) ], [ call.duration_minutes, call.time_label, call.ends_at ], "a call is a quarter of an hour unless said"
  end

  test "the usual duration follows the kind, unless one was given" do
    assign
    assign(kind: "call")
    assert_equal 15, follow_up.duration_minutes
    assign(kind: "visit")
    assert_equal 60, follow_up.duration_minutes
    assign(kind: "call", duration_minutes: 60)
    assert_equal 60, follow_up.duration_minutes, "given with the change, it's kept"
    assign(kind: "visit", duration_minutes: 90)
    assign(kind: "call")
    assert_equal 90, follow_up.duration_minutes, "not the usual one, so it's kept"
  end

  test "moving, handing on and changing details are each recorded, and the people concerned are told" do
    assign(timing: "exact", start_time: "14:00")
    assign(scheduled_on: Date.new(2026, 11, 24), timing: "window", start_time: "13:00", window_end_time: "15:00")
    assign(user: @sam, instructions: "Bring the ladder")
    assign(kind: "call", instructions: "Ring first")

    assert_equal %w[assigned rescheduled reassigned updated updated], history.map(&:first)
    reassigned = as_business(@business) { @request.events.find_by(kind: "reassigned") }
    assert_equal [ @pat.id, @sam.id ], reassigned.data.values_at("from_user_id", "to_user_id")
    assert_equal [ %w[instructions], %w[kind duration_minutes instructions] ], as_business(@business) { @request.events.where(kind: "updated").map { _1.data["changed"] } }
    assert_equal [ [ "request_assigned", "Yours to follow up: site visit for Maria Lopez, Mon, Nov 23 · 2 pm", nil ],
                   [ "request_changed", "Moved: site visit for Maria Lopez is now Tue, Nov 24 · Arrive 1–3 pm", nil ],
                   [ "request_changed", "No longer yours: site visit for Maria Lopez, Tue, Nov 24 · Arrive 1–3 pm", "It's been given to someone else on the team." ] ], notices(@pat)
    assert_equal [ [ "request_assigned", "Yours to follow up: site visit for Maria Lopez, Tue, Nov 24 · Arrive 1–3 pm", "Bring the ladder" ],
                   [ "request_changed", "Changed: call with Maria Lopez, Tue, Nov 24 · Arrive 1–3 pm", "Ring first" ] ], notices(@sam)
    assert_empty notices(@owner), "whoever makes the change isn't told"
    assert_raises(ActiveRecord::ReadOnlyRecord) { as_business(@business) { @request.events.first.update!(kind: "ended") } }
  end

  test "the notices are emailed unless the person turned them off" do
    as_business(@business) { BusinessUser.find_by(user: @sam).update!(notification_emails: { "request_assigned" => false }) }
    assert_enqueued_emails(1) { assign }
    assert_enqueued_emails(1) { assign(user: @sam) } # Pat hears it's gone; Sam turned off emails for it
    assert_equal 1, as_business(@business) { Notification.where(user: @sam).count }, "still in the app"
  end

  test "unassigning, setting back to New, archiving and quoting take it off the assignee; a closed request can't be assigned" do
    assign
    as_business(@business) { @request.reload.follow_up.end!(by: @owner) }
    assert_nil follow_up
    assign
    as_business(@business) { @request.reload.move_to!("new", by: @owner) }
    assert_nil follow_up, "back in the pile"
    assign
    as_business(@business) { @request.reload.move_to!("archived", by: @sam) }
    assert_equal [ [ "assigned", nil ], [ "unassigned", nil ], [ "assigned", nil ], [ "unassigned", nil ], [ "assigned", nil ], [ "ended", "archived" ] ], history
    assert_equal [ "No longer yours: site visit for Maria Lopez, Mon, Nov 23 · Anytime", "The request was archived." ], notices(@pat).last.last(2)
    assert_raises(RequestFollowUp::NotOpen) { assign }

    as_business(@business) { @request.move_to!("in_progress") }
    assign
    as_business(@business) { @request.reload.create_quote!(by: @owner) }
    assert_equal [ "ended", "quoted" ], history.last
    assert_equal 0, as_business(@business) { RequestFollowUp.count }
  end

  test "archiving takes the request's lock, as assigning does" do
    assign
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { as_business(@business) { @request.reload.move_to!("archived", by: @owner) } }
    assert sql.any? { _1.include?("FOR UPDATE") && _1.include?("service_requests") }, "move_to! locks the request"
  end

  test "only active members of this business who can see requests can be assigned, on every change" do
    error = assert_raises(ActiveRecord::RecordInvalid) { assign(user: users(:two)) }
    assert_match "Only people on your team who can see requests", error.message
    tech = member("Tia", :technician)
    assert_raises(ActiveRecord::RecordInvalid, "until JOB-06 shows follow-ups on My day") { assign(user: tech) }
    assert_raises(ActiveRecord::RecordInvalid) { assign(user: nil) }

    assign
    as_business(@business) { BusinessUser.where(user: @pat).update_all(active: false) } # no callbacks: as if they left mid-change
    assert_raises(ActiveRecord::RecordInvalid) { assign(start_time: "10:00", timing: "exact") }
  end

  test "deactivating or removing the assignee ends their follow-ups, in the history, and the requests go back to New" do
    assign
    other = as_business(@business) { ServiceRequest.create!(client: @maria, source: "phone", description: "Gutters") }
    assign(other, user: @sam)
    Current.user = @owner
    as_business(@business) { BusinessUser.find_by(user: @pat).deactivate! }
    assert_nil follow_up
    assert_equal [ "new", [ "ended", "left_team" ] ], [ as_business(@business) { @request.reload.status }, history.last ]
    assert_equal @owner, as_business(@business) { @request.events.last.user }

    third = as_business(@business) { ServiceRequest.create!(client: @maria, source: "phone", description: "Deck") }
    tia = member("Tia", :admin)
    assign(third, user: tia)
    as_business(@business) { BusinessUser.find_by(user: tia).update!(role: "technician") }
    assert_equal [ "new", nil, "role_changed" ], as_business(@business) { [ third.reload.status, third.follow_up, third.events.last.data["reason"] ] },
                 "a role that can't see requests ends it too"

    @business.remove_user(@sam)
    assert_equal [ "new", nil ], as_business(@business) { [ other.reload.status, other.follow_up ] }
    assert_equal "left_team", as_business(@business) { other.events.last.data["reason"] }
  ensure
    Current.reset
  end

  test "deleting the assignee's account ends their follow-ups; erasing the client removes it, and scrubs its history and notices" do
    assign
    assert @pat.delete_account!
    assert_nil follow_up
    assert_equal [ "new", [ "ended", "left_team" ] ], [ as_business(@business) { @request.reload.status }, history.last ]

    assign(user: @sam, instructions: "Ask Maria Lopez about the dog")
    as_business(@business) { ClientErasure.new(@maria, by: @owner).erase! }
    assert_nil follow_up
    as_business(@business) do
      assert_no_match(/Maria Lopez/, Notification.where(subject: @request).map { "#{_1.title} #{_1.body}" }.join)
      assert_no_match(/Maria Lopez/, @request.events.map { _1.data.to_json }.join)
    end
  end

  test "warnings: outside the hours, and overlapping the assignee's visits and other follow-ups, both ways, in few queries" do
    unsaved = as_business(@business) { ServiceRequest.new(client: @maria).build_follow_up(user: @pat, scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "18:00").tap(&:validate) }
    assert_equal [ "That's outside your hours (8 am–5 pm)." ], as_business(@business) { VisitWarnings.for([ unsaved ]) }

    assign(scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "10:00")
    as_business(@business) do
      job = Job.create!(client: @maria, title: "Spring cleanup")
      visit = job.visits.new(scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "09:30", duration_minutes: 90, assignee_ids: [ @pat.id ]).tap(&:validate)
      assert_equal [ "Pat has a site visit for Maria Lopez then (10 am)." ], VisitWarnings.for([ visit ])
      visit.schedule!(by: @owner)
      3.times do |n|
        other = ServiceRequest.create!(client: @maria, source: "phone", description: "Other #{n}")
        RequestFollowUp.assign!(other, { user: @pat, scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "15:00" }, by: @owner)
      end
      call = ServiceRequest.create!(client: @maria, source: "phone", description: "Gutters")
                           .build_follow_up(user: @pat, kind: "call", scheduled_on: Date.new(2026, 11, 24), timing: "exact", start_time: "10:30").tap(&:validate)
      warnings = nil
      queries = count_queries { warnings = VisitWarnings.for([ call ]) }
      assert_equal [ "Pat is on #{job.number} Spring cleanup then (9:30 am).", "Pat has a site visit for Maria Lopez then (10 am)." ], warnings
      assert_operator queries, :<=, 12, "one load per kind of record, not one per follow-up"
      assert_empty VisitWarnings.for([ @request.reload.follow_up ]).grep(/site visit/), "a follow-up doesn't overlap itself"
    end
  end

  test "a request at a location in another time zone is booked, labelled and checked on that location's clock" do
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    as_business(@business) do
      denver = Location.create!(name: "Denver yard", timezone: "America/Denver", weekly_hours: { "1" => { "opens" => "07:00", "closes" => "12:00" } })
      @request.update!(location: denver)
    end
    follow_up = assign(timing: "exact", start_time: "11:30")
    assert_equal [ Time.utc(2026, 11, 23, 18, 30), "Mon, Nov 23 · 11:30 am" ], [ follow_up.starts_at, follow_up.when_label ]
    late = as_business(@business) { follow_up.tap { _1.assign_attributes(start_time: "13:00") }.tap(&:validate) }
    assert_equal [ "That's outside your hours (7 am–12 pm)." ], as_business(@business) { VisitWarnings.for([ late ]) }
  end

  test "a booked site visit is one line on the client's timeline, kept up to date; calls aren't there" do
    assign(kind: "call")
    assert_empty as_business(@business) { @maria.events.where(kind: "follow_up_booked") }
    assign(kind: "visit")
    assign(scheduled_on: Date.new(2026, 11, 25))
    assign(kind: "call")
    assign(kind: "visit")
    assert_equal [ "Wed, Nov 25, 2026 · Anytime" ], as_business(@business) { @maria.events.where(kind: "follow_up_booked").map { _1.data["when"] } }
  end

  test "the requests export says who's following each up" do
    assign(kind: "call")
    csv, = as_business(@business) { DataExport.table("requests").generate }
    row = CSV.parse(csv, headers: true).first
    assert_equal [ "Call", "Pat", "2026-11-23" ], row.values_at("Follow-up", "Assigned to", "Follow-up day")
  end

  test "another business's requests and members can't be used" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Theirs")
    end
    assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { RequestFollowUp.create!(service_request: theirs, user: @pat, scheduled_on: Date.current) } }
    as_business(@business) { assert_empty ServiceRequest.where(id: theirs.id) }
  end

  private

  def count_queries(&)
    count = 0
    callback = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    count
  end
end
