# NTF-05: how many bounce and complaint reports arrived each day (UTC), and how many matched a
# client email or were dropped. Counts only, for the ops console's Email events card.
class EmailEventTally < ApplicationRecord
  COUNTS = %i[received matched dropped].freeze
  INCREMENTS = {
    received: Arel.sql("received = email_event_tallies.received + 1"),
    matched: Arel.sql("matched = email_event_tallies.matched + 1"),
    dropped: Arel.sql("dropped = email_event_tallies.dropped + 1")
  }.freeze
  SUMS = Arel.sql("COALESCE(SUM(received), 0), COALESCE(SUM(matched), 0), COALESCE(SUM(dropped), 0)")

  def self.count!(name, day: Time.now.utc.to_date)
    name = name.to_sym
    upsert({ day:, name => 1 }, unique_by: :day, on_duplicate: INCREMENTS.fetch(name))
  end

  # Sums over the last `days` days, today included.
  def self.recent(days: 7, today: Time.now.utc.to_date)
    COUNTS.zip(where(day: (today - (days - 1))..today).pick(SUMS).map(&:to_i)).to_h
  end
end
