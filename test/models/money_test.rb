require "test_helper"

class MoneyTest < ActiveSupport::TestCase
  test "parses decimal strings exactly" do
    assert_equal 1250, Money.parse("12.50", "USD").cents
    assert_equal 125_000, Money.parse("1,250.00", "USD").cents
    assert_equal 30, Money.parse("0.1", "USD").cents + Money.parse("0.2", "USD").cents
    assert_equal(-405, Money.parse("-4.05", "GBP").cents)
    assert_equal 1001, Money.parse("10.005", "USD").cents # half-up
  end

  test "rejects floats, junk and unknown currencies" do
    assert_raises(ArgumentError) { Money.parse(0.1, "USD") }
    assert_raises(ArgumentError) { Money.parse("abc", "USD") }
    assert_raises(Money::UnknownCurrency) { Money.parse("1", "JPY") }
    assert_raises(ArgumentError) { Money.new(1.5, "USD") }
  end

  test "adds and subtracts only within a currency" do
    usd = Money.new(1000, "USD")
    assert_equal Money.new(1500, "USD"), usd + Money.new(500, "USD")
    assert_equal Money.new(500, "USD"), usd - Money.new(500, "USD")
    assert_raises(Money::CurrencyMismatch) { usd + Money.new(1, "CAD") }
  end

  test "multiplies by exact factors with half-up rounding" do
    assert_equal 3750, (Money.new(1250, "USD") * 3).cents
    assert_equal 1875, (Money.new(1250, "USD") * BigDecimal("1.5")).cents
    assert_equal 1, (Money.new(1, "USD") * BigDecimal("0.5")).cents
    assert_equal 0, (Money.new(1, "USD") * BigDecimal("0.49")).cents
    assert_equal 33, (Money.new(100, "USD") * Rational(1, 3)).cents
    assert_raises(ArgumentError) { Money.new(100, "USD") * 1.1 }
  end

  test "allocates without losing a cent" do
    parts = Money.new(1000, "USD").allocate([ 1, 1, 1 ])
    assert_equal [ 334, 333, 333 ], parts.map(&:cents)
    assert_equal [ 0, 0 ], Money.new(0, "USD").allocate([ 1, 1 ]).map(&:cents)
    weighted = Money.new(100, "USD").allocate([ 2000, 1000, 1 ])
    assert_equal 100, weighted.sum(&:cents)
    assert_equal [ 67, 33, 0 ], weighted.map(&:cents)
    assert_equal(-1000, Money.new(-1000, "USD").allocate([ 1, 1, 1 ]).sum(&:cents))
  end

  test "formats with the currency symbol and separators" do
    assert_equal "$1,250.00", Money.new(125_000, "USD").format
    assert_equal "£0.05", Money.new(5, "GBP").format
    assert_equal "-€4.10", Money.new(-410, "EUR").format
    assert_equal "CA$12.00", Money.new(1200, "CAD").format
    assert_equal "Free", Money.zero("USD").format(display_zero_as: "Free")
    assert_equal "12.50", Money.new(1250, "AUD").to_s
  end

  test "compares and works as a hash key" do
    assert Money.new(2, "USD") > Money.new(1, "USD")
    assert_nil Money.new(1, "USD") <=> Money.new(1, "CAD")
    assert_equal 1, [ Money.new(5, "USD"), Money.new(5, "USD") ].uniq.size
    assert Money.new(5, "USD").frozen?
  end

  test "sums a list in one currency" do
    assert_equal Money.new(6, "USD"), Money.sum([ Money.new(1, "USD"), Money.new(5, "USD") ], "USD")
    assert_equal Money.zero("USD"), Money.sum([], "USD")
  end
end
