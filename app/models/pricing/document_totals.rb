module Pricing
  # The one implementation of quote and invoice arithmetic. Quotes, invoices and their PDFs
  # all call this; nothing else adds up line items. Rules (ADR 0013):
  #
  # 1. Line amount = quantity × unit price, rounded half-up to the cent.
  # 2. A line discount (percent or fixed, never more than the line) comes off that line.
  # 3. Subtotal = sum of discounted lines.
  # 4. A document discount comes off the subtotal and is spread across lines in proportion
  #    to their amounts (cent-exact; never onto a PAY-08 credit), so each tax rate sees its
  #    correct base.
  #    PAY-08: the quote's discount an invoice applies (`share`: [[tax rates, Money]], spread over
  #    the quote's tax mix) comes off after its own discount, before tax, at those rates; a line's
  #    share of its quote line's fixed discount comes off that line (Line#share).
  #    Progress credited (PAY-08) is a credit line (Line#credit): what that invoice charged, net
  #    of its discounts, taken off after this one's discount and before tax.
  # 5. Tax is calculated once per rate on the sum of the lines carrying it, then rounded,
  #    not per line. Rates on the same line apply side by side, never compounded.
  # 6. Tax-inclusive prices: the tax inside each group of lines sharing the same rates is
  #    extracted (gross ÷ (1 + rates)), split between rates by percentage, and the total
  #    stays what the client saw on the lines.
  #
  #   totals = Pricing::DocumentTotals.new(
  #     currency: "USD",
  #     lines: [ Pricing::Line.new(quantity: 2, unit_price: Money.parse("40", "USD"), tax_rates: [ state ]) ],
  #     discount: Pricing::Discount.percent(10)
  #   )
  #   totals.subtotal, totals.discount, totals.taxes, totals.total
  class DocumentTotals
    LineResult = Data.define(:line, :amount, :discount, :subtotal, :taxable)
    TaxResult = Data.define(:rate, :base, :amount)

    attr_reader :currency, :lines, :discount, :share, :credit_total, :taxes, :subtotal, :total

    def initialize(currency:, lines:, discount: nil, prices_include_tax: false, share: nil)
      @currency = Money.currency(currency).code
      @prices_include_tax = prices_include_tax
      @share_parts = Array(share).reject { _2.zero? }.map { |rates, amount| [ Array(rates), check_currency(amount) ] }
      @share = Money.sum(@share_parts.map(&:last), @currency)
      compute(lines, discount)
      freeze
    end

    def prices_include_tax? = @prices_include_tax

    def tax_total = Money.sum(taxes.map(&:amount), currency)

    # Total before tax (for tax-inclusive documents, the total with the tax taken out).
    def net_total = total - tax_total

    private

    def compute(raw_lines, document_discount)
      line_amounts = raw_lines.map { |line| check_currency(line.unit_price) * line.quantity }
      line_discounts = raw_lines.zip(line_amounts).map { |line, amount| line_discount_for(line, amount) }
      line_subtotals = line_amounts.zip(line_discounts).map { |amount, off| amount - off }

      # PAY-08: a credit is money already charged, net of that invoice's discounts: it isn't in the
      # subtotal or discounted again, and comes off after the discount, before tax.
      work = raw_lines.each_index.reject { raw_lines[_1].credit }
      @subtotal = Money.sum(work.map { line_subtotals[_1] }, currency)
      @credit_total = Money.sum(raw_lines.each_index.select { raw_lines[_1].credit }.map { line_subtotals[_1] }, currency)
      own = [ discount_for(document_discount, @subtotal), [ @subtotal, Money.zero(currency) ].max ].min
      spread = own.allocate(raw_lines.zip(line_subtotals).map { |line, amount| line.credit ? 0 : amount.cents })
      taxable = line_subtotals.zip(spread).map { |amount, share| amount - share }
      @discount = own + @share

      @lines = raw_lines.each_with_index.map do |line, i|
        LineResult.new(line:, amount: line_amounts[i], discount: line_discounts[i], subtotal: line_subtotals[i], taxable: taxable[i])
      end
      # The quote's discount, part by tax mix, taxed as negative amounts at its rates.
      taxed_lines = raw_lines + @share_parts.map { |rates, amount| Pricing::Line.new(quantity: 1, unit_price: Money.zero(currency) - amount, tax_rates: rates, credit: true) }
      taxed = taxable + @share_parts.map { Money.zero(currency) - _2 }
      @taxes = prices_include_tax? ? inclusive_taxes(taxed_lines, taxed) : exclusive_taxes(taxed_lines, taxed)
      after_discount = @subtotal - @discount + @credit_total
      @total = prices_include_tax? ? after_discount : after_discount + Money.sum(@taxes.map(&:amount), currency)
    end

    def exclusive_taxes(raw_lines, taxable)
      rates_in_order(raw_lines).map do |rate|
        base = Money.sum(raw_lines.each_index.select { |i| raw_lines[i].tax_rates.include?(rate) }.map { |i| taxable[i] }, currency)
        TaxResult.new(rate:, base:, amount: base * (rate.percent / 100))
      end
    end

    def inclusive_taxes(raw_lines, taxable)
      amounts = Hash.new { |hash, rate| hash[rate] = Money.zero(currency) }
      bases = Hash.new { |hash, rate| hash[rate] = Money.zero(currency) }

      raw_lines.each_index.group_by { |i| raw_lines[i].tax_rates.uniq }.each do |rates, indexes|
        next if rates.empty?

        gross = Money.sum(indexes.map { |i| taxable[i] }, currency)
        combined = rates.sum(&:percent)
        net = Money.new((BigDecimal(gross.cents) / (1 + (combined / 100))).round(0, Money::ROUNDING).to_i, currency)
        (gross - net).allocate(rates.map(&:percent)).zip(rates).each do |share, rate|
          amounts[rate] += share
          bases[rate] += net
        end
      end

      rates_in_order(raw_lines).map { |rate| TaxResult.new(rate:, base: bases[rate], amount: amounts[rate]) }
    end

    def rates_in_order(raw_lines) = raw_lines.flat_map(&:tax_rates).uniq

    # Its own discount, then its share (never more than what's left of the line).
    def line_discount_for(line, amount)
      off = discount_for(line.discount, amount)
      return off unless line.share&.positive? && amount.positive?

      off + [ check_currency(line.share), amount - off ].min
    end

    def discount_for(discount, amount)
      # No discount on nothing, or on credit lines (negative amounts).
      return Money.zero(currency) if discount.nil? || !amount.positive?

      off = discount.percent? ? amount * (discount.value / 100) : check_currency(discount.value)
      [ off, amount ].min
    end

    def check_currency(money)
      raise Money::CurrencyMismatch, "Document is #{currency}, got #{money.currency}" unless money.currency == currency

      money
    end
  end
end
