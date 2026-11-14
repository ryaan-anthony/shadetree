# Money columns on Active Record models: an integer `<name>_cents` column, with the currency
# taken from the record (usually its business).
#
#   class LineItem < ApplicationRecord
#     include HasMoney
#     money :unit_price, currency: -> { quote.business.currency }
#   end
#
#   item.unit_price = "12.50"   # stores unit_price_cents = 1250
#   item.unit_price             # => #<Money 12.50 USD>
#
# Blank input stores nil. Unparseable input stores nil and adds a validation error, so
# forms can show "Unit price is not a valid amount" instead of saving zero.
module HasMoney
  extend ActiveSupport::Concern

  class_methods do
    def money(name, currency: -> { business.currency })
      column = "#{name}_cents"
      invalid = "@_#{name}_invalid_input"

      define_method(name) do
        cents = self[column]
        cents.nil? ? nil : Money.new(cents, instance_exec(&currency))
      end

      define_method("#{name}=") do |value|
        instance_variable_set(invalid, nil)
        self[column] =
          case value
          when nil, "" then nil
          when Money
            expected = instance_exec(&currency)
            raise Money::CurrencyMismatch, "#{name} is #{expected}, got #{value.currency}" unless value.currency == expected

            value.cents
          else
            Money.parse(value, instance_exec(&currency)).cents
          end
      rescue ArgumentError => error
        raise if error.is_a?(Money::CurrencyMismatch)

        instance_variable_set(invalid, value)
        self[column] = nil
      end

      # Keeps what the user typed in the form when it couldn't be parsed.
      define_method("#{name}_before_type_cast") do
        instance_variable_get(invalid) || public_send(name)&.to_s
      end

      validate do
        errors.add(name, :not_a_money_amount, message: "is not a valid amount") if instance_variable_get(invalid)
      end
    end
  end
end
