require "test_helper"

# CAT-07: visits keep their location's time zone; warnings and reminders use its hours and
# clock; automations can be limited to a location (NTF-04 left that condition to CAT-07).
class LocationSchedulingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5, plan_overrides: { "features" => { "locations" => true } })
    @owner = users(:one)
    Tenancy.with_business(@business) do
      @denver = Location.create!(name: "Denver yard", timezone: "America/Denver", weekly_hours: { "3" => { "opens" => "10:00", "closes" => "14:00" } })
      @client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @job = Job.create!(client: @client, title: "Xeriscape", location: @denver)
    end
  end

  def visit(on, start = "09:00") = Tenancy.with_business(@business) { @job.visits.new(scheduled_on: on, timing: "exact", start_time: start, duration_minutes: 60) }

  test "a visit's times are in its location's zone" do
    v = visit(Date.new(2026, 11, 18))
    v.valid?
    assert_equal Time.utc(2026, 11, 18, 16), v.starts_at, "9 am in Denver"
    assert_equal "9 am", Tenancy.with_business(@business) { v.time_label }
  end

  test "warnings use the location's hours" do
    wednesday = Date.new(2026, 11, 18)
    early = visit(wednesday, "09:00").tap(&:valid?)
    fine = visit(wednesday, "11:00").tap(&:valid?)
    Tenancy.with_business(@business) do
      assert_equal [ "That's outside your hours (10 am–2 pm)." ], VisitWarnings.for([ early ])
      assert_empty VisitWarnings.for([ fine ]), "11 am fits Denver's hours though the main location opens at 8"
      thursday = visit(Date.new(2026, 11, 19), "11:00").tap(&:valid?)
      assert_equal [ "You're closed on Thursdays." ], VisitWarnings.for([ thursday ])
    end
  end

  test "reminders go at 10 am in the location's zone" do
    Tenancy.with_business(@business) { visit(Date.new(2026, 12, 10), "11:00").schedule!(by: @owner, notify_client: false) }
    reminders = -> { Tenancy.with_business(@business) { EmailMessage.where(kind: "visit_reminder").count } }
    travel_to(Time.utc(2026, 12, 9, 15, 30)) { VisitRemindersJob.perform_now } # 10:30 in New York, 8:30 in Denver
    assert_equal 0, reminders.call
    travel_to(Time.utc(2026, 12, 9, 17, 5)) { VisitRemindersJob.perform_now } # 10:05 in Denver
    assert_equal 1, reminders.call
  end

  test "an automation can be limited to a location" do
    Tenancy.with_business(@business) do
      quote = Quote.start(client: @client, location: @denver)
      assert_nil AutomationConditions.failing({ "location" => @denver.uid }, quote)
      assert_equal "Only for New York; this is for Denver yard.", AutomationConditions.failing({ "location" => @business.primary_location.uid }, quote)
      v = visit(Date.new(2026, 11, 18))
      assert_nil AutomationConditions.failing({ "location" => @denver.uid }, v), "a visit goes by its job"

      rule = AutomationRule.new(name: "Denver follow-up", trigger: "quote_sent", delay_minutes: 0, conditions: { "location" => "nope" },
                                actions: [ { "type" => "notify_team", "team" => "office" } ])
      assert_not rule.valid?
      assert_includes rule.errors[:conditions], "need one of your locations"
      theirs = businesses(:two).primary_location
      rule.conditions = { "location" => theirs.uid }
      assert_not rule.valid?, "another business's location"
    end
  end
end
