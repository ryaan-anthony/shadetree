module Pricing
  # One row on a quote or invoice. quantity may be fractional ("1.5" hours); unit_price is Money.
  Line = Data.define(:quantity, :unit_price, :discount, :tax_rates) do
    def initialize(quantity:, unit_price:, discount: nil, tax_rates: [])
      quantity = quantity.is_a?(String) ? BigDecimal(quantity) : quantity
      raise ArgumentError, "quantity must not be a Float" if quantity.is_a?(Float)

      super(quantity: Money.decimal(quantity), unit_price:, discount:, tax_rates: Array(tax_rates))
    end
  end
end
