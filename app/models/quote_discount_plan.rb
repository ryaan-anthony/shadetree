# PAY-08 (owner, 2026-11-23): how an invoice applies an amount of its quote's discount, line by
# line. The quote's discount has a mix (what its taxed and its untaxed lines carry of it); the work
# invoices together give exactly the discount, in that mix where the work allows, so tax matches
# the quote's. Each amount comes off the lines actually charged and lowers tax at their own rates:
# a job taxed otherwise than its quote pays tax on less, and the tax total then differs. An invoice
# applies its amount:
#
# 1. first what each group needs now: what the work left after it, in that group, can't absorb;
# 2. then the rest in proportion to what each group can still take (its maximum less its need).
#
# A group's amount only comes off its own lines (B20: the quote's taxed/untaxed mix). Lines first
# take only what leaves this invoice's credits whole (`free`: progress is capped by what the final
# charges); more only when it must go now. A part's `from` is the group it counts
# against, `key` the line it comes off and `rates` that line's (so tax and a progress invoice's
# credit use one base). Nothing is dropped: the amount is never more than the groups' maximums.
#
#   slots = [ Slot.new(key: "a", group: [ state ], rates: [ state ], capacity: 800_00, free: 800_00),
#             Slot.new(key: "b", group: [], rates: [], capacity: 100_00, free: 100_00) ]
#   QuoteDiscountPlan.new(outstanding: { [ state ] => 50_00, [] => 50_00 }, slots:).parts(100_00)
#   # => [Part(from: [state], key: "a", cents: 5000), Part(from: [], key: "b", cents: 5000)]
class QuoteDiscountPlan
  Slot = Data.define(:key, :group, :rates, :capacity, :free)
  Part = Data.define(:from, :key, :rates, :cents)

  attr_reader :outstanding, :slots, :needs, :maxes

  def initialize(outstanding:, slots:, needs: {}, maxes: nil)
    @outstanding = outstanding.select { _2.positive? }
    @slots = slots.select { _1.capacity.positive? }.map { _1.with(free: _1.free.clamp(0, _1.capacity)) }
    @needs = needs
    @maxes = maxes || @outstanding.to_h { |group, owed| [ group, [ owed, capacity(group) ].min ] }
  end

  def capacity(group) = own(group).sum(&:capacity)
  def free(group) = own(group).sum(&:free)

  # Each group's needs first, then the rest in proportion to what each can still take (its maximum
  # less its need); each group's amount only off its own lines.
  def parts(cents)
    @placed = Hash.new(0)
    @parts = Hash.new(0)
    amounts = Hash.new(0)
    left = cents
    outstanding.each_key do |group|
      amount = [ needs.fetch(group, 0), left ].min.clamp(0..)
      amounts[group] += amount
      left -= amount
    end
    weights = outstanding.keys.map { |group| [ group, maxes.fetch(group, 0) - amounts[group] ] }.select { _2.positive? }
    split([ left, weights.sum(&:last) ].min, weights).each { |group, part| amounts[group] += part } if left.positive? && weights.any?
    amounts.each { |group, amount| place(group, amount) if amount.positive? }
    @parts.map { |(from, slot), part| Part.new(from:, key: slot.key, rates: slot.rates, cents: part) }
  end

  private

  def own(group) = slots.select { _1.group == group }

  def split(cents, weights) = Money.new(cents, "USD").allocate(weights.map(&:last)).zip(weights).filter_map { |part, (key, _)| [ key, part.cents ] if part.positive? }

  # Off its own lines' free room (no credit is cut), then what's left of them.
  def place(group, cents)
    mine = own(group)
    [ :free, :capacity ].each do |kind|
      break unless cents.positive?

      rooms = mine.map { [ _1, [ _1.public_send(kind) - @placed[_1.key], 0 ].max ] }.select { _2.positive? }
      next if rooms.empty?

      amount = [ cents, rooms.sum(&:last) ].min
      split(amount, rooms).each { |slot, part| record(group, slot, part) }
      cents -= amount
    end
  end

  def record(from, slot, cents)
    @parts[[ from, slot ]] += cents
    @placed[slot.key] += cents
  end
end
