# The period billable usage counts in (BIL-02): the calendar month in the business's time zone
# for a free plan, or the billing cycle of a paid plan: monthly from its anchor (the
# subscription's start, BIL-04), counted in UTC as the provider does, so daylight saving and a
# change of time zone never move it. An anchor on the 31st renews on the last day of shorter
# months. Before the anchor (or with none), calendar months apply.
#
#   period = UsagePeriod.for(business)
#   period.range           # => Nov 1 00:00 EST ... Dec 1 00:00 EST
#   period.resets_on       # => Dec 1 (a date, in the business's zone)
#   period.billing_cycle?  # => false on a calendar month
#   period.used            # => 3 quotes sent in it
UsagePeriod = Data.define(:business, :starts_at, :ends_at, :billing_cycle) do
  def self.for(business, at: Time.current)
    anchor = business.billing_cycle_anchor&.utc
    if anchor.nil? || business.plan.free? || at < anchor
      start = at.in_time_zone(business.time_zone).beginning_of_month
      finish = start.next_month
      finish = anchor.in_time_zone(business.time_zone) if anchor && !business.plan.free? && anchor < finish # the month the cycles start in ends there
      return new(business:, starts_at: start, ends_at: finish, billing_cycle: false)
    end

    at = at.utc
    months = (at.year * 12 + at.month) - (anchor.year * 12 + anchor.month)
    months -= 1 if anchor.advance(months:) > at
    zone = business.time_zone
    new(business:, starts_at: anchor.advance(months:).in_time_zone(zone), ends_at: anchor.advance(months: months + 1).in_time_zone(zone), billing_cycle: true)
  end

  def billing_cycle? = billing_cycle
  def range = starts_at...ends_at
  def resets_on = ends_at.to_date

  # Quotes sent in the period: one indexed count (business, kind, time).
  def used(kind = "quote_sent") = Tenancy.with_business(business) { UsageEvent.where(kind:, occurred_at: range).count }

  # This period and the ones before it, newest first (for operators). Each is worked out as it
  # was: calendar months before a paid plan's anchor, billing cycles after it.
  def history(count: 24)
    periods = [ self ]
    (count - 1).times { periods << UsagePeriod.for(business, at: periods.last.starts_at - 1.second) }
    periods
  end
end
