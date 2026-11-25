require "test_helper"

# PAY-08 (B20): a group's part of the quote's discount only comes off its own lines, in the quote's
# taxed/untaxed mix: its need first, then up to its maximum.
class QuoteDiscountPlanTest < ActiveSupport::TestCase
  setup do
    @state = [ Pricing::TaxRate.new(name: "State", percent: "10") ]
    @slots = [ QuoteDiscountPlan::Slot.new(key: "roof", group: @state, rates: @state, capacity: 200_00, free: 30_00),
               QuoteDiscountPlan::Slot.new(key: "haul", group: [], rates: [], capacity: 100_00, free: 100_00) ]
  end

  def parts(plan, cents) = plan.parts(cents).group_by(&:key).transform_values { |list| list.map { [ _1.from, _1.cents ] } }

  test "a forced minimum beyond a group's free room comes off its own lines, not the other group's" do
    plan = QuoteDiscountPlan.new(outstanding: { @state => 100_00, [] => 50_00 }, slots: @slots, needs: { @state => 80_00 })
    assert_equal({ "roof" => [ [ @state, 80_00 ] ] }, parts(plan, 80_00), "the taxed $80 off the roof, past its free $30, never off the untaxed haul")
  end

  test "the maximum spreads by what each group can still take, each off its own lines" do
    plan = QuoteDiscountPlan.new(outstanding: { @state => 100_00, [] => 50_00 }, slots: @slots, maxes: { @state => 30_00, [] => 50_00 })
    assert_equal({ "roof" => [ [ @state, 30_00 ] ], "haul" => [ [ [], 50_00 ] ] }, parts(plan, 80_00))
  end
end
