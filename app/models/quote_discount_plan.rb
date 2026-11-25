# PAY-08 (owner, 2026-11-23): how an invoice applies an amount of its quote's discount, by tax.
# The quote's discount has a tax mix (what its taxed and untaxed lines, at each set of rates,
# carry of it); the work invoices together give exactly the discount, and in that mix, so total
# tax matches the quote's. An invoice applies its amount:
#
# 1. first what each group needs now: what the work left after it, at those rates, can't absorb;
# 2. then the rest in proportion to what each group can still take at its own rates;
# 3. more than that only off other lines (the most it offers stops at `fits`, unless needed).
#
# Each group's amount comes off this invoice's lines at its own rates while they can take it, and
# what they can't (no such lines here, or too little) off its other lines, at theirs. Lines first
# take only what leaves this invoice's credits whole (`free`: a final's progress is capped by what
# it charges), and more only when it must go now. A part's
# `rates` are the lines it comes off (so tax and the credit of a progress invoice use one base),
# its `from` the group it counts against. Nothing is dropped: the amount is never more than the
# invoice charges.
#
#   plan = QuoteDiscountPlan.new(outstanding: { [] => 50_00, [state] => 50_00 }, capacity: { [state] => 800_00 }, needs: {})
#   plan.parts(100_00) # => [Part(from: [], rates: [state], cents: 5000), Part(from: [state], rates: [state], cents: 5000)]
class QuoteDiscountPlan
  Part = Data.define(:from, :rates, :cents)

  attr_reader :outstanding, :capacity, :free, :needs

  def initialize(outstanding:, capacity:, free: capacity, needs: {})
    @outstanding = outstanding.select { _2.positive? }
    @capacity = capacity.select { _2.positive? }
    @free = @capacity.to_h { |group, can| [ group, free.fetch(group, can).clamp(0, can) ] }
    @needs = needs
  end

  def parts(cents)
    @placed = Hash.new(0)
    @parts = Hash.new(0)
    taken = Hash.new(0)
    left = cents
    outstanding.each do |group, owed|
      amount = [ needs.fetch(group, 0), owed, left ].min.clamp(0..)
      next unless amount.positive?

      place(group, amount)
      taken[group] += amount
      left -= amount
    end
    # The rest off lines at their own group's rates, in proportion to what each can take...
    weights = outstanding.map { |group, owed| [ group, [ owed - taken[group], free.fetch(group, 0) - @placed[group] ].min ] }.select { _2.positive? }
    if left.positive? && weights.any?
      amount = [ left, weights.sum(&:last) ].min
      Money.new(amount, "USD").allocate(weights.map(&:last)).zip(weights) do |part, (group, _)|
        place(group, part.cents)
        taken[group] += part.cents
      end
      left -= amount
    end
    # ...and only then, if more is asked than fits, off other lines (the tax then differs).
    weights = outstanding.map { |group, owed| [ group, owed - taken[group] ] }.select { _2.positive? }
    if left.positive? && weights.any?
      Money.new(left, "USD").allocate(weights.map(&:last)).zip(weights) { |part, (group, _)| place(group, part.cents) if part.positive? }
    end
    @parts.map { |(from, rates), cents| Part.new(from:, rates:, cents:) }
  end

  # The most it applies keeping each group at its own rates.
  def fits = outstanding.sum { |group, owed| [ owed, free.fetch(group, 0) ].min }

  private

  # Off lines at its own rates first (what's free, then the rest they charge: the tax follows the
  # quote's), then off the invoice's other lines, by what they can still take (free first).
  def place(group, cents)
    [ free, capacity ].each do |room|
      inside = [ cents, room.fetch(group, 0) - @placed[group] ].min.clamp(0..)
      record(group, group, inside)
      cents -= inside
    end
    [ free, capacity ].each do |room|
      break unless cents.positive?

      spare = room.map { |rates, can| [ rates, can - @placed[rates] ] }.select { _2.positive? }
      next if spare.empty?

      amount = [ cents, spare.sum(&:last) ].min
      Money.new(amount, "USD").allocate(spare.map(&:last)).zip(spare) { |part, (rates, _)| record(group, rates, part.cents) }
      cents -= amount
    end
    record(group, group, cents) # can't happen: the amount is at most what it charges
  end

  def record(from, rates, cents)
    return unless cents.positive?

    @parts[[ from, rates ]] += cents
    @placed[rates] += cents
  end
end
