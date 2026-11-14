module Pricing
  # A named tax rate, e.g. TaxRate.new(name: "State", percent: "6.25").
  TaxRate = Data.define(:name, :percent) do
    def initialize(name:, percent:)
      percent = BigDecimal(percent.to_s)
      raise ArgumentError, "Tax percent must be between 0 and 100" unless percent.between?(0, 100)

      super(name:, percent:)
    end
  end
end
