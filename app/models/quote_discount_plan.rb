# PAY-08 (owner, 2026-11-23): how an invoice applies an amount of its quote's discount, line by
# line. The quote's discount has a mix (what its taxed and its untaxed lines carry of it); the work
# invoices together give exactly the discount, in that mix where the work allows, so tax matches
# the quote's. Each amount comes off the lines actually charged and lowers tax at their own rates:
# a job taxed otherwise than its quote pays tax on less, and the tax total then differs. An invoice
# applies its amount:
#
# 1. first what each group needs now: what the work left after it, in that group, can't absorb;
# 2. then the rest in proportion to what each group's lines can take (`fits`);
# 3. more than that only when it must (the minimum), off other lines.
#
# A group's amount comes off its own lines while they have room, then off the invoice's other
# lines. Lines first take only what leaves this invoice's credits whole (`free`: progress is capped
# by what the final charges); more only when it must go now. A part's `from` is the group it counts
# against, `key` the line it comes off and `rates` that line's (so tax and a progress invoice's
# credit use one base). Nothing is dropped: the amount is never more than the invoice charges.
#
#   slots = [ Slot.new(key: "a", group: [ state ], rates: [ state ], capacity: 800_00, free: 800_00) ]
#   QuoteDiscountPlan.new(outstanding: { [ state ] => 50_00, [] => 50_00 }, slots:).parts(100_00)
#   # => [Part(from: [state], key: "a", cents: 5000), Part(from: [], key: "a", cents: 5000)]
class QuoteDiscountPlan
  Slot = Data.define(:key, :group, :rates, :capacity, :free)
  Part = Data.define(:from, :key, :rates, :cents)

  attr_reader :outstanding, :slots, :needs

  def initialize(outstanding:, slots:, needs: {})
    @outstanding = outstanding.select { _2.positive? }
    @slots = slots.select { _1.capacity.positive? }.map { _1.with(free: _1.free.clamp(0, _1.capacity)) }
    @needs = needs
  end

  # The most it applies off each group's own lines, keeping its credits whole.
  def fits = outstanding.sum { |group, owed| [ owed, own(group).sum(&:free) ].min }

  def capacity(group) = own(group).sum(&:capacity)

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
    # The rest off each group's own lines, in proportion to the room they have...
    weights = outstanding.map { |group, owed| [ group, [ owed - taken[group], room(own(group), :free) ].min ] }.select { _2.positive? }
    if left.positive? && weights.any?
      amount = [ left, weights.sum(&:last) ].min
      split(amount, weights).each do |group, part|
        place(group, part)
        taken[group] += part
      end
      left -= amount
    end
    # ...and only then, if more must go, off other lines.
    weights = outstanding.map { |group, owed| [ group, owed - taken[group] ] }.select { _2.positive? }
    split(left, weights).each { |group, part| place(group, part) } if left.positive? && weights.any?
    @parts.map { |(from, slot), part| Part.new(from:, key: slot.key, rates: slot.rates, cents: part) }
  end

  private

  def own(group) = slots.select { _1.group == group }

  def room(list, kind) = list.sum { [ _1.public_send(kind) - @placed[_1.key], 0 ].max }

  def split(cents, weights) = Money.new(cents, "USD").allocate(weights.map(&:last)).zip(weights).filter_map { |part, (key, _)| [ key, part.cents ] if part.positive? }

  # Off its own lines' free room, then other lines' (the money stays right: no credit is cut), then
  # what's left of its own lines, then of the others.
  def place(group, cents)
    mine = own(group)
    others = slots - mine
    [ [ mine, :free ], [ others, :free ], [ mine, :capacity ], [ others, :capacity ] ].each do |list, kind|
      break unless cents.positive?

      rooms = list.map { [ _1, [ _1.public_send(kind) - @placed[_1.key], 0 ].max ] }.select { _2.positive? }
      next if rooms.empty?

      amount = [ cents, rooms.sum(&:last) ].min
      split(amount, rooms).each { |slot, part| record(group, slot, part) }
      cents -= amount
    end
    record(group, mine.first || slots.first, cents) if cents.positive? && slots.any? # can't happen: never more than it charges
  end

  def record(from, slot, cents)
    @parts[[ from, slot ]] += cents
    @placed[slot.key] += cents
  end
end
