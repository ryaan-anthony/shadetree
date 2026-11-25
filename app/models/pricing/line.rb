module Pricing
  # One row on a quote or invoice. quantity may be fractional ("1.5" hours); unit_price is Money.
  # share (PAY-08) is a fixed amount off on top of its discount: an invoice line's share of its
  # quote line's fixed discount. credit marks a credit for money billed earlier (PAY-08), which a
  # document discount isn't spread onto.
  # fixed_tax ({ rate => Money }, credits only): the tax that credit carries, as the invoice it
  # credits charged it, taken off each rate's tax instead of being worked out again (PAY-08).
  Line = Data.define(:quantity, :unit_price, :discount, :tax_rates, :share, :credit, :fixed_tax) do
    def initialize(quantity:, unit_price:, discount: nil, tax_rates: [], share: nil, credit: false, fixed_tax: nil)
      quantity = quantity.is_a?(String) ? BigDecimal(quantity) : quantity
      raise ArgumentError, "quantity must not be a Float" if quantity.is_a?(Float)

      super(quantity: Money.decimal(quantity), unit_price:, discount:, tax_rates: Array(tax_rates), share:, credit:, fixed_tax:)
    end
  end
end
