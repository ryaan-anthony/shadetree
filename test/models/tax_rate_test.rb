require "test_helper"

# CAT-04: tax rates.
class TaxRateTest < ActiveSupport::TestCase
  setup { @business = businesses(:one) }

  def rate(name = "State", percent = "6.25", **attributes) = as_business(@business) { TaxRate.create!(name:, percent:, **attributes) }

  test "validates name and percent" do
    as_business(@business) do
      bad = TaxRate.new(name: " ", percent: "0")
      assert_not bad.valid?
      assert bad.errors.of_kind?(:name, :blank)
      assert bad.errors.of_kind?(:percent, :greater_than)
      assert_not TaxRate.new(name: "X", percent: "100.5").valid?
      assert_not TaxRate.new(name: "X", percent: "abc").valid?
      too_precise = TaxRate.new(name: "X", percent: "6.12345")
      assert_not too_precise.valid?
      assert_includes too_precise.errors[:percent], "can have at most 4 decimal places"
      assert TaxRate.new(name: "X", percent: "6.1234").valid?
    end
  end

  test "names are unique among active rates, ignoring case" do
    state = rate
    as_business(@business) do
      assert_not TaxRate.new(name: "state", percent: 5).valid?
      state.archive!
      assert TaxRate.create!(name: "State", percent: 7)
      assert_not state.reload.update(archived_at: nil), "restoring would duplicate an active name"
    end
    as_business(businesses(:two)) { assert TaxRate.create!(name: "State", percent: 5) }
  end

  test "at most ten active rates" do
    10.times { rate("Rate #{_1}", 1) }
    as_business(@business) do
      extra = TaxRate.new(name: "Eleven", percent: 1)
      assert_not extra.valid?
      assert_match "up to 10", extra.errors[:base].first
    end
  end

  test "percent label" do
    assert_equal "6.25%", rate.percent_label
    assert_equal "7%", rate("County", "7.0").percent_label
    assert_equal "0.0625%", rate("Tiny", "0.0625").percent_label
    assert_equal "County 7%", rate("County 2", "7").label.sub(" 2", "")
  end

  test "new documents get the default set, none for exempt clients, none without rates" do
    as_business(@business) { assert_empty TaxRate.for_new_document }
    state = rate("State", "6.25")
    county = rate("County", "1.5")
    rate("Hotel", "5", applies_by_default: false)
    archived = rate("Old", "3")
    as_business(@business) do
      archived.archive!
      assert_equal [ state.to_pricing, county.to_pricing ], TaxRate.for_new_document
      exempt = Client.create!(display_name: "Church", tax_exempt: true, contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      assert_empty TaxRate.for_new_document(client: exempt)
    end
  end

  test "two rates show separately on a document and editing a rate leaves the copy alone" do
    state = rate("State", "6.25")
    county = rate("County", "1.5")
    applied = as_business(@business) { TaxRate.for_new_document }
    as_business(@business) { state.update!(percent: "9") }

    line = Pricing::Line.new(quantity: 1, unit_price: Money.parse("100", "USD"), tax_rates: applied)
    totals = Pricing::DocumentTotals.new(currency: "USD", lines: [ line ])
    assert_equal [ [ "State", Money.parse("6.25", "USD") ], [ "County", Money.parse("1.50", "USD") ] ],
                 totals.taxes.map { [ _1.rate.name, _1.amount ] }
    assert_equal Money.parse("107.75", "USD"), totals.total
    assert_equal BigDecimal("1.5"), county.to_pricing.percent
  end

  test "rates belong to one business" do
    mine = rate
    as_business(businesses(:two)) do
      assert_empty TaxRate.all
      assert_nil TaxRate.find_by(id: mine.id)
    end
  end
end
