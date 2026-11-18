# An exact amount of money: an integer count of minor units (cents) plus a currency.
# Never use Float for money. See docs/adr/0013-money-time-and-numbering.md.
#
#   price = Money.parse("12.50", "USD")   # => #<Money 12.50 USD>
#   price * 3                             # => #<Money 37.50 USD>
#   price.format                          # => "$12.50"
#   Money.new(1999, "GBP").format         # => "£19.99"
#
# Arithmetic between different currencies raises Money::CurrencyMismatch.
# Multiplying by a fraction rounds half-up to the nearest minor unit.
class Money
  include Comparable

  class CurrencyMismatch < ArgumentError; end
  class UnknownCurrency < ArgumentError; end

  Currency = Data.define(:code, :symbol, :exponent, :name)

  # Launch currencies. Adding one is a data change here plus Business validation.
  CURRENCIES = {
    "USD" => Currency.new("USD", "$", 2, "US dollar"),
    "CAD" => Currency.new("CAD", "CA$", 2, "Canadian dollar"),
    "GBP" => Currency.new("GBP", "£", 2, "Pound sterling"),
    "EUR" => Currency.new("EUR", "€", 2, "Euro"),
    "AUD" => Currency.new("AUD", "A$", 2, "Australian dollar")
  }.freeze

  ROUNDING = BigDecimal::ROUND_HALF_UP

  attr_reader :cents, :currency

  def self.currency(code)
    CURRENCIES.fetch(code.to_s.upcase) { raise UnknownCurrency, "Unsupported currency #{code.inspect}" }
  end

  def self.zero(currency_code) = new(0, currency_code)

  # From a decimal amount in major units: "12.50", 12.5r, BigDecimal("12.5"), "1,250.00".
  # Floats are rejected: by the time a value is a Float it may already be inexact.
  def self.parse(amount, currency_code)
    raise ArgumentError, "Use a String, Integer, Rational or BigDecimal for money, not Float" if amount.is_a?(Float)

    decimal = amount.is_a?(String) ? BigDecimal(amount.strip.delete(",").delete_prefix("$")) : self.decimal(amount)
    raise ArgumentError, "Not finite" unless decimal.finite? # "Infinity", "NaN"

    currency = self.currency(currency_code)
    new((decimal * (10**currency.exponent)).round(0, ROUNDING).to_i, currency.code)
  rescue ArgumentError, TypeError => error
    raise if error.is_a?(UnknownCurrency) || error.message.start_with?("Use a String")

    raise ArgumentError, "Not a money amount: #{amount.inspect}"
  end

  # Exact BigDecimal for Integer, BigDecimal, Rational or a decimal String.
  def self.decimal(value)
    value.is_a?(Rational) ? BigDecimal(value, 34) : BigDecimal(value)
  end

  def self.sum(amounts, currency_code)
    amounts.inject(zero(currency_code), :+)
  end

  def initialize(cents, currency_code)
    raise ArgumentError, "cents must be an Integer, got #{cents.class}" unless cents.is_a?(Integer)

    @cents = cents
    @currency = self.class.currency(currency_code).code
    freeze
  end

  def currency_info = self.class.currency(currency)

  # Major units as an exact decimal, for display maths and APIs that want "12.50".
  def amount
    BigDecimal(cents) / (10**currency_info.exponent)
  end

  def to_s
    pad(amount.round(currency_info.exponent).to_s("F"))
  end

  def +(other) = with_same_currency(other) { self.class.new(cents + other.cents, currency) }
  def -(other) = with_same_currency(other) { self.class.new(cents - other.cents, currency) }
  def -@ = self.class.new(-cents, currency)

  # Multiply by a quantity or rate. Rounds half-up to a whole minor unit.
  def *(factor)
    raise ArgumentError, "Multiply money by Integer, Rational or BigDecimal, not #{factor.class}" if factor.is_a?(Float) || factor.is_a?(Money)

    self.class.new((BigDecimal(cents) * self.class.decimal(factor)).round(0, ROUNDING).to_i, currency)
  end

  # Split into parts that add up exactly, spreading leftover cents from the first part on.
  # allocate([1, 1, 1]) on $10.00 gives $3.34, $3.33, $3.33.
  def allocate(weights)
    weights = weights.map { |w| self.class.decimal(w) }
    total = weights.sum
    return weights.map { self.class.zero(currency) } if total.zero?

    shares = weights.map { |w| (BigDecimal(cents) * w / total) }
    floors = shares.map { |s| s.floor.to_i }
    remainder = cents - floors.sum
    order = shares.each_with_index.sort_by { |share, index| [ -(share - share.floor), index ] }.map(&:last)
    order.first(remainder.abs).each { |index| floors[index] += remainder <=> 0 }
    floors.map { |c| self.class.new(c, currency) }
  end

  def zero? = cents.zero?
  def positive? = cents.positive?
  def negative? = cents.negative?
  def abs = self.class.new(cents.abs, currency)

  def <=>(other)
    return nil unless other.is_a?(Money) && other.currency == currency

    cents <=> other.cents
  end

  def ==(other) = other.is_a?(Money) && other.currency == currency && other.cents == cents
  alias eql? ==
  def hash = [ cents, currency ].hash

  # "$1,250.00", "-£4.10". English number formatting with the currency's symbol for every
  # launch currency (decision in ADR 0013).
  def format(display_zero_as: nil)
    return display_zero_as if zero? && display_zero_as

    digits = ActiveSupport::NumberHelper.number_to_delimited(abs.to_s)
    "#{"-" if negative?}#{currency_info.symbol}#{digits}"
  end

  def inspect = "#<Money #{self} #{currency}>"

  private

  def pad(string)
    whole, fraction = string.split(".")
    exponent = currency_info.exponent
    exponent.zero? ? whole : "#{whole}.#{(fraction || "").ljust(exponent, "0")}"
  end

  def with_same_currency(other)
    raise ArgumentError, "Expected Money, got #{other.class}" unless other.is_a?(Money)
    raise CurrencyMismatch, "Cannot combine #{currency} and #{other.currency}" unless other.currency == currency

    yield
  end
end
