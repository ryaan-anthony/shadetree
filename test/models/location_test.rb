require "test_helper"

# CAT-07: locations, their details, hours and time zones, and the plan gate.
class LocationTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5, plan_overrides: { "features" => { "locations" => true } })
  end

  def branch(**attrs) = as_business(@business) { Location.create!(name: "Denver yard", timezone: "America/Denver", phone: "555-0199", city: "Denver", **attrs) }

  test "a new business gets a main location from its profile" do
    business = Business.create!(name: "Fresh Co", owner: users(:one), city: "Austin", plan: plans(:free))
    main = business.primary_location
    assert main.primary?
    assert_equal "Austin", main.name
    assert_not business.multiple_locations?
    assert_equal Location::PRIMARY_NAME, Business.create!(name: "No City", owner: users(:two), plan: plans(:free)).primary_location.name
  end

  test "the main location's details are the business profile's; others have their own" do
    main = @business.primary_location
    assert_equal @business.address_lines, main.address_lines
    assert_equal [ @business.phone, @business.email ], [ main.contact_phone, main.contact_email ]
    denver = branch
    assert_equal [ "Denver" ], denver.address_lines
    assert_equal "555-0199", denver.contact_phone
    assert_equal @business.email, denver.contact_email, "no email of its own: the business's"
    assert_equal "America/Denver", denver.time_zone.tzinfo.identifier
    assert_equal @business.weekly_hours, denver.weekly_hours, "starts with the business's hours"
    assert @business.reload.multiple_locations?
  end

  test "each location's hours, closures and time zone decide when it's open" do
    denver = branch(weekly_hours: { "3" => { "opens" => "10:00", "closes" => "14:00" } })
    as_business(@business) { Closure.create!(reason: "Stocktake", starts_on: Date.new(2026, 11, 25), location: denver) }
    wednesday = Date.new(2026, 11, 18)
    main_hours, denver_hours = OpeningHours.new(@business), OpeningHours.new(denver)
    assert main_hours.open_at?(@business.local_time(wednesday, "09:00"))
    assert_not denver_hours.open_at?(denver.local_time(wednesday, "09:00"))
    assert denver_hours.open_at?(denver.local_time(wednesday, "10:00"))
    assert_not denver_hours.open_at?(@business.local_time(wednesday, "10:00")), "10 am in New York is 8 am in Denver"
    assert_not denver_hours.open_on?(Date.new(2026, 11, 25)), "its own closure"
    assert main_hours.open_on?(Date.new(2026, 11, 25)), "a branch's closure doesn't close the main location"
    assert_equal [ "That's outside your hours (10 am–2 pm)." ], denver_hours.problems(wednesday, denver.local_time(wednesday, "15:00"), denver.local_time(wednesday, "16:00")).map(&:message)
  end

  test "adding a location needs the plan feature; existing ones stay" do
    denver = branch
    @business.update!(plan_overrides: {})
    error = assert_raises(ActiveRecord::RecordInvalid) { branch(name: "Boulder") }
    assert_match "isn't included in your plan", error.message
    assert as_business(@business) { denver.reload.update!(phone: "555-0100") }, "existing locations can still be edited"
    as_business(@business) { denver.archive! }
    assert_raises(ArgumentError) { as_business(@business) { denver.restore! } }
  end

  test "names are unique per business and the main location can't be archived" do
    branch
    assert_raises(ActiveRecord::RecordInvalid) { branch(name: "denver YARD") }
    assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { @business.primary_location.archive! } }
  end

  test "a member's documents start at their default location, else the one they work at, else the main one" do
    member = business_users(:one)
    assert_equal @business.primary_location, member.document_location
    denver, boulder = branch, branch(name: "Boulder")
    as_business(@business) { LocationMember.create!(location: denver, user: member.user) }
    assert_equal denver, member.reload.document_location
    as_business(@business) { LocationMember.create!(location: boulder, user: member.user) }
    assert_equal @business.primary_location, member.reload.document_location, "two places and no default: the main one"
    member.update!(default_location: boulder)
    assert_equal boulder, member.reload.document_location
    as_business(@business) { boulder.archive! }
    assert_equal denver, member.reload.document_location, "an archived default doesn't count"
  end

  test "locations belong to one business" do
    branch
    assert_equal 1, as_business(businesses(:two)) { Location.count }
    member = business_users(:two)
    member.default_location = @business.primary_location
    assert_not as_business(businesses(:two)) { member.valid? }
  end
end
