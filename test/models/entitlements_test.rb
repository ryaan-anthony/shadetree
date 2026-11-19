require "test_helper"

# BIL-01: plans and the one entitlement check: the default plan, limits (and unlimited),
# features, per-business overrides, and what's in use.
class EntitlementsTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
  end

  test "every business is on exactly one plan; new ones get the default (Free)" do
    assert_equal plans(:free), @business.plan
    created = Business.create!(owner: @owner, name: "Second Shop", industry: "landscaping", timezone: "America/New_York")
    assert_equal plans(:free), created.plan
  end

  test "limits, features and unlimited come from the plan; overrides comp one business" do
    entitlements = @business.entitlements
    assert_equal 5, entitlements.limit(:quotes_sent)
    assert_not entitlements.feature?(:remove_powered_by)
    assert_raises(ArgumentError) { entitlements.feature?(:made_up) }
    assert_raises(ArgumentError) { entitlements.limit(:made_up) }

    @business.update!(plan: plans(:business))
    entitlements = @business.reload.entitlements
    assert_nil entitlements.limit(:quotes_sent)
    assert entitlements.unlimited?(:team_members)
    assert_nil entitlements.remaining(:team_members)
    assert entitlements.within?(:team_members, adding: 1_000)
    assert entitlements.feature?(:remove_powered_by)

    @business.update!(plan: plans(:free), plan_overrides: { "limits" => { "quotes_sent" => 50, "team_members" => nil }, "features" => { "remove_powered_by" => true } })
    entitlements = @business.reload.entitlements
    assert_equal 50, entitlements.limit(:quotes_sent)
    assert entitlements.unlimited?(:team_members), "an override can make a limit unlimited"
    assert entitlements.feature?(:remove_powered_by)
    assert Branding.new(@business).show_powered_by? == false
  end

  test "usage: team members count active members and pending invitations; quotes sent this month" do
    Tenancy.with_business(@business) do
      entitlements = @business.entitlements
      assert_equal 1, entitlements.used(:team_members)
      assert_equal 1, entitlements.remaining(:team_members)
      Invitation.create!(email: "new@example.com", role: "technician", invited_by: @owner)
      assert_equal 2, Entitlements.for(@business).used(:team_members)
      assert_not Entitlements.for(@business).within?(:team_members)

      client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:)
      UsageEvent.record!("quote_sent", quote, at: 2.months.ago)
      UsageEvent.record!("quote_sent", Quote.start(client:))
      assert_equal 1, Entitlements.for(@business).used(:quotes_sent), "only this month counts"
    end
  end

  test "plans sync from the seed file without overwriting edits, and validate their keys" do
    plans(:free).update!(limits: { "quotes_sent" => 9, "team_members" => 2 })
    written = Plan.sync!
    assert_includes written, "pro"
    assert_not_includes written, "free"
    assert_equal 9, plans(:free).reload.limits["quotes_sent"]
    bad = Plan.new(key: "x", name: "X", limits: { "widgets" => 1 }, features: { "teleport" => true })
    assert_not bad.valid?
    assert_match "unknown keys: widgets", bad.errors[:limits].join
    assert_match "unknown keys: teleport", bad.errors[:features].join
    assert_not Plan.new(key: "y", name: "Y", limits: { "quotes_sent" => -1 }).valid?
  end
end
