# What a priced document shares (quotes, jobs and invoices): its tax rates, its totals from
# Pricing::DocumentTotals (PLT-08), and the *_cents total columns, a cache for lists refreshed on
# every save. The including model has `currency`, `tax_rates` (jsonb), `prices_include_tax`, the
# discount columns (HasDiscount) and `line_items` whose class includes DocumentLine.
module PricedDocument
  extend ActiveSupport::Concern

  included do
    include HasMoney
    include HasDiscount

    validate :tax_rates_are_valid
    before_save :cache_totals
  end

  def discount_currency = currency

  def tax_rate_list = tax_rates.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  # Replaces the document's tax rates with these (name/percent pairs or Pricing::TaxRate).
  def tax_rate_list=(rates)
    self.tax_rates = Array(rates).map { |rate| { "name" => rate.name.to_s, "percent" => rate.percent.to_d.to_s("F") } }.uniq
  end

  def totals
    Pricing::DocumentTotals.new(currency:, discount: pricing_discount, prices_include_tax:,
                                lines: current_line_items.map { _1.to_pricing(tax_rate_list) })
  end

  # Lines as a builder sees them: in order, without ones being removed.
  def current_line_items = line_items.reject(&:marked_for_destruction?).sort_by { [ _1.position, _1.id || 0 ] }

  def subtotal = Money.new(subtotal_cents, currency)
  def total = Money.new(total_cents, currency)

  private

  def cache_totals
    result = totals
    self.subtotal_cents = result.subtotal.cents
    self.discount_total_cents = (result.discount + Money.sum(result.lines.map(&:discount), currency)).cents
    self.tax_cents = result.tax_total.cents
    self.total_cents = result.total.cents
  end

  def tax_rates_are_valid
    return errors.add(:tax_rates, "must be a list") unless tax_rates.is_a?(Array)

    tax_rate_list
  rescue ArgumentError, TypeError
    errors.add(:tax_rates, "must each have a name and a percent from 0 to 100")
  end
end
