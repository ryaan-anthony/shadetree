require "test_helper"

class Pricing::DocumentTotalsTest < ActiveSupport::TestCase
  def usd(amount) = Money.parse(amount, "USD")

  def line(quantity, price, **options) = Pricing::Line.new(quantity:, unit_price: usd(price), **options)

  def totals(lines, **options) = Pricing::DocumentTotals.new(currency: "USD", lines:, **options)

  setup do
    @state = Pricing::TaxRate.new(name: "State", percent: "6.25")
    @county = Pricing::TaxRate.new(name: "County", percent: "1.5")
  end

  test "quantity times unit price, rounded half-up per line" do
    result = totals([ line("1.5", "33.33"), line("0.335", "3") ])
    assert_equal [ usd("50.00"), usd("1.01") ], result.lines.map(&:amount) # 49.995 → 50.00; 1.005 → 1.01
    assert_equal usd("51.01"), result.subtotal
    assert_equal usd("51.01"), result.total
  end

  test "line discounts by percent and by amount, never below zero" do
    result = totals([
      line(1, "100", discount: Pricing::Discount.percent(10)),
      line(1, "20", discount: Pricing::Discount.amount(usd("25")))
    ])
    assert_equal [ usd("10"), usd("20") ], result.lines.map(&:discount)
    assert_equal usd("90"), result.subtotal
  end

  test "document discount is spread across lines so each tax rate gets the right base" do
    result = totals(
      [ line(1, "100", tax_rates: [ @state ]), line(1, "50") ],
      discount: Pricing::Discount.amount(usd("15"))
    )
    assert_equal usd("150"), result.subtotal
    assert_equal usd("15"), result.discount
    assert_equal [ usd("90"), usd("45") ], result.lines.map(&:taxable)
    assert_equal usd("90"), result.taxes.first.base
    assert_equal usd("5.63"), result.taxes.first.amount # 90 × 6.25% = 5.625 → 5.63
    assert_equal usd("140.63"), result.total
  end

  test "tax is calculated per rate on the summed base, not per line" do
    # Per line: 3 × round(0.10 × 6.25%) = 3 × 0.01 = 0.03. Per rate on the sum: 0.30 × 6.25% = 0.02.
    result = totals(Array.new(3) { line(1, "0.10", tax_rates: [ @state ]) })
    assert_equal usd("0.02"), result.tax_total
  end

  test "multiple rates on a line apply side by side, not compounded" do
    result = totals([ line(1, "200", tax_rates: [ @state, @county ]), line(1, "100", tax_rates: [ @state ]) ])
    assert_equal [ "State", "County" ], result.taxes.map { _1.rate.name }
    assert_equal [ usd("300"), usd("200") ], result.taxes.map(&:base)
    assert_equal [ usd("18.75"), usd("3.00") ], result.taxes.map(&:amount)
    assert_equal usd("321.75"), result.total
    assert_equal usd("300"), result.net_total
  end

  test "tax-inclusive prices keep the total and extract the tax" do
    vat = Pricing::TaxRate.new(name: "VAT", percent: 20)
    result = totals([ line(1, "120", tax_rates: [ vat ]), line(1, "10") ], prices_include_tax: true)
    assert_equal usd("130"), result.total
    assert_equal usd("20"), result.tax_total
    assert_equal usd("100"), result.taxes.first.base
    assert_equal usd("110"), result.net_total
  end

  test "tax-inclusive with two rates splits the extracted tax by percentage and adds up" do
    gst = Pricing::TaxRate.new(name: "GST", percent: 5)
    pst = Pricing::TaxRate.new(name: "PST", percent: 7)
    result = totals([ line(1, "99.99", tax_rates: [ gst, pst ]) ], prices_include_tax: true)
    assert_equal usd("99.99"), result.total
    assert_equal usd("89.28") + result.tax_total, result.total # 99.99 / 1.12 = 89.276… → 89.28
    assert_equal [ usd("4.46"), usd("6.25") ], result.taxes.map(&:amount)
  end

  test "credit lines (negative quantities) reduce the total and get no discount" do
    result = totals([ line(1, "100"), line(-1, "25", discount: Pricing::Discount.percent(50)) ])
    assert_equal Money.zero("USD"), result.lines.last.discount
    assert_equal usd("75"), result.total
  end

  test "empty documents total zero" do
    result = totals([])
    assert_equal Money.zero("USD"), result.total
    assert_empty result.taxes
  end

  test "rejects mixed currencies and invalid inputs" do
    assert_raises(Money::CurrencyMismatch) do
      totals([ Pricing::Line.new(quantity: 1, unit_price: Money.parse("1", "CAD")) ])
    end
    assert_raises(ArgumentError) { Pricing::Line.new(quantity: 1.5, unit_price: usd("1")) }
    assert_raises(ArgumentError) { Pricing::Discount.percent(120) }
    assert_raises(ArgumentError) { Pricing::Discount.amount(usd("-1")) }
    assert_raises(ArgumentError) { Pricing::TaxRate.new(name: "x", percent: -1) }
  end

  test "property: totals always reconcile to the cent" do
    rng = Random.new(42)
    rates = [ @state, @county, Pricing::TaxRate.new(name: "Other", percent: "8.875") ]
    200.times do
      lines = Array.new(rng.rand(1..6)) do
        line(BigDecimal(rng.rand(1..400)) / 4, format("%.2f", rng.rand(0.0..500.0)),
             discount: rng.rand < 0.3 ? Pricing::Discount.percent(rng.rand(0..50)) : nil,
             tax_rates: rates.sample(rng.rand(0..2), random: rng))
      end
      inclusive = rng.rand < 0.3
      result = totals(lines, discount: rng.rand < 0.4 ? Pricing::Discount.percent(rng.rand(0..30)) : nil, prices_include_tax: inclusive)

      assert_equal result.subtotal, Money.sum(result.lines.map(&:subtotal), "USD")
      assert_equal result.subtotal - result.discount, Money.sum(result.lines.map(&:taxable), "USD")
      expected = inclusive ? result.subtotal - result.discount : result.subtotal - result.discount + result.tax_total
      assert_equal expected, result.total
    end
  end

  test "PAY-08: a document discount isn't spread onto a credit, but still is onto a typed negative line; shares come off" do
    typed = totals([ line(1, "100"), line(1, "-20") ], discount: Pricing::Discount.percent(10))
    assert_equal [ usd("90"), usd("-18") ], typed.lines.map(&:taxable)
    credited = totals([ line(1, "100", tax_rates: [ @state ]), line(1, "-20", credit: true, tax_rates: [ @state ]) ], discount: Pricing::Discount.percent(10))
    assert_equal [ usd("90"), usd("-20") ], credited.lines.map(&:taxable), "a credit isn't discounted again"
    assert_equal [ usd("100"), usd("10"), usd("-20") ], [ credited.subtotal, credited.discount, credited.credit_total ]
    assert_equal usd("70") + credited.tax_total, credited.total
    shared = Pricing::DocumentTotals.new(currency: "USD", lines: [ line(2, "50", share: usd("15")) ], share: usd("10"))
    assert_equal [ usd("85"), usd("10"), usd("75") ], [ shared.subtotal, shared.discount, shared.total ]
  end
end
