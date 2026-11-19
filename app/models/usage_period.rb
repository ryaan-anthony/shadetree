# The period billable usage counts in (BIL-02): the calendar month in the business's time zone
# for a free plan, or the billing cycle of a paid plan, monthly from its anchor (the
# subscription's start, BIL-04). Months of different lengths are handled the way providers do:
# an anchor on the 31st renews on the last day of shorter months.
#
#   period = UsagePeriod.for(business)
#   period.range      # => Nov 1 00:00 EST ... Dec 1 00:00 EST
#   period.resets_on  # => Dec 1 (a date, in the business's zone)
#   period.used       # => 3 quotes sent in it
UsagePeriod = Data.define(:business, :starts_at, :ends_at) do
  def self.for(business, at: Time.current)
    zone = business.time_zone
    at = at.in_time_zone(zone)
    anchor = business.billing_cycle_anchor
    if anchor.nil? || business.plan.free?
      start = at.beginning_of_month
      new(business:, starts_at: start, ends_at: start.next_month)
    else
      anchor = anchor.in_time_zone(zone)
      months = ((at.year * 12 + at.month) - (anchor.year * 12 + anchor.month))
      start = anchor.advance(months:)
      start = anchor.advance(months: months - 1) if start > at
      new(business:, starts_at: start, ends_at: anchor.advance(months: ((start.year * 12 + start.month) - (anchor.year * 12 + anchor.month)) + 1))
    end
  end

  def range = starts_at...ends_at
  def resets_on = ends_at.to_date

  # Quotes sent in the period: one indexed count (business, kind, time).
  def used(kind = "quote_sent") = Tenancy.with_business(business) { UsageEvent.where(kind:, occurred_at: range).count }

  # The periods before this one, newest first, with their counts (for operators).
  def history(count: 24)
    periods = [ self ]
    (count - 1).times { periods << UsagePeriod.for(business, at: periods.last.starts_at - 1.second) }
    periods
  end
end
