require "test_helper"

# JOB-12: "On my way": the arrival time (rounded, on the location's clock), its warnings, who may
# send it, the limits, when an update emails, who the client sees, and when the card goes.
class VisitOnTheWayTest < ActiveSupport::TestCase
  include PermissionHelpers
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", show_team_profiles: true, client_visit_emails: { "on_my_way" => "1" },
                      plan_overrides: { "features" => { "locations" => true }, "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @marcus = member_with_role(:technician).tap { _1.update!(first_name: "Marcus", last_name: "Reed") }
    @dee = member_with_role(:technician).tap { _1.update!(first_name: "Dee", last_name: "Park") }
    Tenancy.with_business(@business) do
      @client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @job = Job.create!(client: @client, title: "Spring cleanup")
    end
  end

  def zone = ActiveSupport::TimeZone["America/New_York"]
  def at(local) = zone.parse(local)

  def book(on: Date.new(2026, 12, 10), timing: "window", start: "09:00", finish: "12:00", crew: [ @marcus.id, @dee.id ])
    Tenancy.with_business(@business) do
      @job.visits.new(scheduled_on: on, timing:, start_time: (start unless timing == "anytime"), window_end_time: (finish if timing == "window"),
                      assignee_ids: crew).tap { _1.schedule!(by: @owner, notify_client: false) }
    end
  end

  def send!(visit, by: @marcus, **choice) = Tenancy.with_business(@business) { visit.reload.send_on_the_way!(visit.on_the_way_arrival(**choice), by:) }
  def sends(visit) = Tenancy.with_business(@business) { visit.events.where(kind: "on_the_way").to_a }

  test "the example: 10:45, 30 minutes, about 11:15 am, inside the 9–12 window, Marcus first" do
    visit = book
    travel_to(at("2026-12-10 10:45")) do
      sent = send!(visit, minutes: 30)
      assert_equal at("2026-12-10 11:15"), sent.arrives_at
      assert sent.emailed && sent.first
      assert_nil visit.on_the_way_warning(sent.arrives_at)
      Tenancy.with_business(@business) do
        assert visit.reload.on_the_way?
        assert_equal "11:15 am", visit.on_the_way_time_label
        assert_equal %w[Marcus Dee], visit.on_the_way_team.map(&:client_first_name)
        assert_equal [ @marcus.id, @dee.id ], visit.client_team_card_user_ids
        assert_equal [ [ "on_the_way", true, nil ] ], sends(visit).map { [ _1.kind, _1.data["emailed"], _1.data["why_not"] ] }
        assert_equal @marcus, sends(visit).sole.user
        event = @client.events.find_by!(kind: "visit_on_the_way")
        assert_equal [ visit, @marcus ], [ event.subject, event.user ]
      end
    end
  end

  test "times round to the nearest 5 minutes; a picked time is later today and 5+ minutes ahead" do
    visit = book
    travel_to(at("2026-12-10 10:47")) do
      assert_equal at("2026-12-10 11:15"), visit.on_the_way_arrival(minutes: 30)
      assert_equal at("2026-12-10 11:00"), visit.on_the_way_arrival(minutes: 15), "11:02 rounds down"
      assert_equal at("2026-12-10 11:30"), visit.on_the_way_arrival(minutes: 45), "11:32 rounds down"
      assert_equal at("2026-12-10 11:35"), visit.on_the_way_arrival(at: "11:33"), "11:33 rounds up"
      assert_equal at("2026-12-10 11:20"), visit.on_the_way_arrival(at: "11:18"), "a picked time rounds up"
      assert_equal at("2026-12-10 10:55"), visit.on_the_way_arrival(at: "10:52"), "8 minutes ahead once rounded up"
      assert_raises(OnTheWay::Refused) { visit.on_the_way_arrival(at: "10:50") }
      assert_equal at("2026-12-10 10:55"), visit.on_the_way_arrival(arrives_at: at("2026-12-10 10:55").utc.iso8601), "a time already chosen"
      assert_raises(OnTheWay::Refused, "past") { visit.on_the_way_arrival(arrives_at: at("2026-12-10 10:45").utc.iso8601) }
      assert_raises(OnTheWay::Refused, "not on a 5-minute mark") { visit.on_the_way_arrival(arrives_at: at("2026-12-10 11:02").utc.iso8601) }
      assert_raises(OnTheWay::Refused) { visit.on_the_way_arrival(at: "nonsense") }
      assert_raises(OnTheWay::Refused) { visit.on_the_way_arrival(minutes: 20) }
    end
    travel_to(at("2026-12-10 23:20")) { assert_raises(OnTheWay::Refused, "past midnight") { visit.on_the_way_arrival(minutes: 60) } }
  end

  test "outside the window, or 15+ minutes from an exact start, warns; anytime doesn't" do
    window, exact, anytime = book, book(timing: "exact", start: "11:00"), book(timing: "anytime")
    assert_equal "That's after the 9 am–12 pm window.", window.on_the_way_warning(at("2026-12-10 12:15"))
    assert_equal "That's before the 9 am–12 pm window.", window.on_the_way_warning(at("2026-12-10 08:45"))
    assert_nil window.on_the_way_warning(at("2026-12-10 12:00"))
    assert_nil exact.on_the_way_warning(at("2026-12-10 11:10"))
    assert_equal "That's 15 minutes after the 11 am start.", exact.on_the_way_warning(at("2026-12-10 11:15"))
    assert_equal "That's 1 hour before the 11 am start.", exact.on_the_way_warning(at("2026-12-10 10:00"))
    assert_nil anytime.on_the_way_warning(at("2026-12-10 18:00"))
  end

  test "only someone going, on a booked visit for today, while the business sends it; erased clients get none" do
    visit = book
    travel_to(at("2026-12-10 10:00")) do
      Tenancy.with_business(@business) do
        assert visit.on_the_way_offered_to?(@marcus)
        assert_not visit.on_the_way_offered_to?(@owner), "not going"
        assert_not book(on: Date.new(2026, 12, 11)).on_the_way_offered_to?(@marcus), "tomorrow"
        @business.update!(client_visit_emails: { "on_my_way" => "0" })
        assert_not visit.reload.on_the_way_offered_to?(@marcus)
        @business.update!(client_visit_emails: { "on_my_way" => "1" })
        visit.start!(by: @marcus)
        assert_not visit.reload.on_the_way_offered_to?(@marcus), "started"
        erased = book
        @client.update_columns(erased_at: Time.current)
        assert_not erased.reload.on_the_way_offered_to?(@marcus), "erased client"
      end
      assert_raises(OnTheWay::Refused) { send!(book, by: @owner, minutes: 15) }
    end
  end

  test "off by default, existing businesses included, and the other visit emails stay on" do
    business = businesses(:two)
    business.update_columns(client_visit_emails: { "scheduled" => true })
    assert_not business.client_visit_email?("on_my_way")
    assert business.client_visit_email?("reminder")
    business.update!(client_visit_emails: { "on_my_way" => "1" })
    assert business.reload.client_visit_email?("on_my_way")
  end

  test "an update emails only 10+ minutes from the time last emailed; any assignee can update and is named first" do
    visit = book
    travel_to(at("2026-12-10 10:45")) { send!(visit, minutes: 30) } # 11:15, emailed
    travel_to(at("2026-12-10 10:50")) { assert_equal "small_change", send!(visit, at: "11:19").why_not } # 11:20
    Tenancy.with_business(@business) do
      assert_equal at("2026-12-10 11:20"), visit.reload.on_the_way_arrives_at, "the card has the latest time"
      assert_equal at("2026-12-10 11:15"), visit.on_the_way_emailed_arrives_at
    end
    travel_to(at("2026-12-10 10:52")) { assert send!(visit, by: @dee, at: "11:23").emailed, "11:25 is 10 from the last email, if only 5 from the last send" }
    Tenancy.with_business(@business) { assert_equal %w[Dee Marcus], visit.reload.on_the_way_team.map(&:client_first_name) }
    assert_equal [ true, false, true ], sends(visit).map { _1.data["emailed"] }
    assert_equal 1, Tenancy.with_business(@business) { @client.events.where(kind: "visit_on_the_way").count }, "only the first is on the timeline"
  end

  test "one send a minute and 5 a day" do
    visit = book
    travel_to(at("2026-12-10 08:00")) { send!(visit, minutes: 15) }
    travel_to(at("2026-12-10 08:00:30")) do
      error = assert_raises(OnTheWay::Refused) { send!(visit, minutes: 30) }
      assert_match "less than a minute ago", error.message
    end
    4.times { |n| travel_to(at("2026-12-10 08:0#{n + 2}")) { send!(visit, minutes: 15) } }
    travel_to(at("2026-12-10 09:00")) { assert_match "That's 5 for this visit today", assert_raises(OnTheWay::Refused) { send!(visit, minutes: 15) }.message }
  end

  test "no usable email, or the hourly client email budget spent: the card still updates, nothing is emailed" do
    visit = book
    Tenancy.with_business(@business) { EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce") }
    travel_to(at("2026-12-10 10:00")) { assert_equal "no_email", send!(visit, minutes: 30).why_not }
    assert Tenancy.with_business(@business) { visit.reload.on_the_way? }
    travel_to(at("2026-12-10 10:02")) do
      Tenancy.with_business(@business) do
        EmailSuppression.clear!("maria@example.com")
        EmailMessage::CLIENT_EMAILS_PER_HOUR.times { EmailMessage.create!(kind: "quote_sent", to: "x#{_1}@example.com") }
      end
      assert_equal "email_limit", send!(visit, minutes: 45).why_not
    end
    assert_nil Tenancy.with_business(@business) { visit.reload.on_the_way_emailed_arrives_at }
  end

  test "deactivated co-assignees are left out; a deactivated or unnamed sender, or profiles off, means the business's name" do
    visit = book
    travel_to(at("2026-12-10 10:45")) { send!(visit, minutes: 30) }
    Tenancy.with_business(@business) do
      @business.business_users.find_by!(user: @dee).update!(active: false)
      assert_equal %w[Marcus], visit.reload.on_the_way_team.map(&:client_first_name)
      @marcus.update_columns(first_name: nil)
      assert_empty visit.on_the_way_team
      assert_empty visit.client_team_card_user_ids, "no photo either"
      @marcus.update_columns(first_name: "Marcus")
      @business.update!(show_team_profiles: false)
      assert_empty visit.reload.on_the_way_team
    end
  end

  test "past the time it's 'any minute' for an hour, then goes; starting, completing, cancelling or moving removes it" do
    visit = book
    travel_to(at("2026-12-10 10:45")) { send!(visit, minutes: 30) }
    travel_to(at("2026-12-10 11:20")) { assert visit.reload.on_the_way_late? }
    travel_to(at("2026-12-10 12:16")) { assert_not visit.reload.on_the_way? }
    Tenancy.with_business(@business) do
      { start: -> { _1.start!(by: @marcus) }, complete: -> { _1.complete!(by: @marcus) }, cancel: -> { _1.cancel!(by: @owner, notify_client: false) },
        move: -> { _1.reschedule!({ start_time: "10:00" }, by: @owner, notify_client: false) } }.each do |what, change|
        other = book
        travel_to(at("2026-12-10 10:45")) do
          send!(other, minutes: 30)
          change.(other.reload)
          assert_not other.reload.on_the_way?, what
          assert_empty other.client_team_card_user_ids, what
        end
      end
      reassigned = book
      travel_to(at("2026-12-10 10:45")) do
        send!(reassigned, minutes: 30)
        reassigned.reload.reschedule!({ assignee_ids: [ @marcus.id ] }, by: @owner, notify_client: false)
        assert_equal %w[Marcus], reassigned.reload.on_the_way_team.map(&:client_first_name), "reassigning only updates the names"
      end
    end
  end

  test "the location's clock in another zone" do
    location = Tenancy.with_business(@business) { Location.create!(name: "West", timezone: "America/Los_Angeles") }
    Tenancy.with_business(@business) { @job.update!(location:) }
    visit = book
    travel_to(ActiveSupport::TimeZone["America/Los_Angeles"].parse("2026-12-10 10:47")) do
      assert_equal "11:15 am", visit.reload.on_the_way_time_label(visit.on_the_way_arrival(minutes: 30))
    end
  end

  test "the repeated hour on a DST day: a time already chosen stays the one picked" do
    exact = book(on: Date.new(2026, 11, 1), timing: "exact", start: "08:00")
    travel_to(Time.utc(2026, 11, 1, 5, 10)) do # 1:10 EDT
      arrival = exact.reload.on_the_way_arrival(minutes: 60) # 1:10 EST, the second 1:10
      assert_equal Time.utc(2026, 11, 1, 6, 10), arrival
      assert exact.on_the_way_warning(arrival), "far before an 8 am start"
      assert_equal arrival, exact.on_the_way_arrival(arrives_at: arrival.utc.iso8601)
    end
  end

  test "a DST day: 1:50 EDT + 30 is 1:20 EST" do
    dst = book(on: Date.new(2026, 11, 1))
    travel_to(at("2026-11-01 01:50")) { assert_equal "1:20 am", dst.reload.on_the_way_time_label(dst.on_the_way_arrival(minutes: 30)) }
  end

  test "the history and timeline name the sender from the account, so deleting it scrubs the name" do
    visit = book
    travel_to(at("2026-12-10 10:45")) { send!(visit, minutes: 30) }
    helper = Object.new.extend(JobsHelper)
    event = sends(visit).sole
    assert_equal "On the way, arriving about 11:15 am (emailed)", helper.visit_event_text(event)
    assert_not event.data.values.join.include?("Marcus")
    timeline = Object.new.extend(ClientEventsHelper).tap { |h| h.define_singleton_method(:admin_job_path) { |job| "/admin/jobs/#{job.uid}" } }
    line = Tenancy.with_business(@business) { timeline.client_event_parts(@client.events.find_by!(kind: "visit_on_the_way")) }
    assert_equal [ "truck", "Marcus was on the way, arriving about 11:15 am" ], line.first(2)
  end
end
