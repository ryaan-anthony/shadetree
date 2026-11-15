require "test_helper"

class HasMoneyTest < ActiveSupport::TestCase
  class PricedThing < ApplicationRecord
    self.table_name = "priced_things"
    include HasMoney
    belongs_to :business
    money :price
    money :deposit, currency: -> { "GBP" }
  end

  setup do
    ActiveRecord::Base.connection.create_table :priced_things, temporary: true do |t|
      t.references :business
      t.integer :price_cents
      t.integer :deposit_cents
    end
    PricedThing.reset_column_information
    @business = businesses(:one)
    @business.update!(currency: "CAD")
  end

  test "reads and writes money in the business's currency" do
    thing = PricedThing.new(business: @business, price: "12.50")
    assert_equal 1250, thing.price_cents
    assert_equal Money.new(1250, "CAD"), thing.price
    thing.price = Money.new(99, "CAD")
    assert_equal 99, thing.price_cents
  end

  test "blank clears; a fixed currency can be declared" do
    thing = PricedThing.new(business: @business, price: "", deposit: "5")
    assert_nil thing.price
    assert_equal "GBP", thing.deposit.currency
  end

  test "unparseable input is a validation error, not zero" do
    thing = PricedThing.new(business: @business, price: "twelve")
    assert_not thing.valid?
    assert_includes thing.errors[:price], "is not a valid amount"
    assert_equal "twelve", thing.price_before_type_cast
    assert_nil thing.price_cents
  end

  test "money in another currency is refused" do
    assert_raises(Money::CurrencyMismatch) { PricedThing.new(business: @business, price: Money.new(1, "USD")) }
  end
end
