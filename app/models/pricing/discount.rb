module Pricing
  # A percentage (BigDecimal 0..100) or a fixed Money amount off.
  Discount = Data.define(:kind, :value) do
    def self.percent(value)
      value = BigDecimal(value.to_s)
      raise ArgumentError, "Discount percent must be between 0 and 100" unless value.between?(0, 100)

      new(kind: :percent, value:)
    end

    def self.amount(money)
      raise ArgumentError, "Discount amount must be Money" unless money.is_a?(Money)
      raise ArgumentError, "Discount amount can't be negative" if money.negative?

      new(kind: :amount, value: money)
    end

    def percent? = kind == :percent
  end
end
