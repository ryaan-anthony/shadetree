# OPS-06: a help search that found nothing, counted by its words only: lower-cased letters,
# at most 100 characters, with anything like an email address or a phone number dropped first
# (as Observability.scrub drops them from logs), and every number with them. One row per words
# per day; kept RETENTION (PruneHelpSearchMissesJob). Operators see them at /ops/help.
class HelpSearchMiss < ApplicationRecord
  RETENTION = 90.days
  MAX = 100

  # "Maria@example.com invoice 555-380-3141" => "invoice"; nil when nothing's left.
  def self.words(query)
    text = query.to_s.unicode_normalize(:nfkc).gsub(Observability::EMAIL, " ").gsub(/\S*@\S*/, " ")
    words = text.downcase.scan(/[[:alpha:]]+(?:['’-][[:alpha:]]+)*/)
    words.each_with_object(+"") { |word, kept| kept << (kept.empty? ? word : " #{word}") if kept.length + word.length + 1 <= MAX }.presence
  end

  def self.record(query, on: Date.current)
    words = words(query) or return
    upsert({ words:, searched_on: on, count: 1 }, unique_by: %i[words searched_on],
           on_duplicate: Arel.sql("count = help_search_misses.count + 1, updated_at = CURRENT_TIMESTAMP"))
  end

  def self.prune! = where(searched_on: ...RETENTION.ago.to_date).delete_all

  # The words searched in the last RETENTION, most often first: [[words, times, last searched on], ...].
  def self.summary(limit: 200)
    where(searched_on: RETENTION.ago.to_date..).group(:words).order(Arel.sql("SUM(count) DESC, MAX(searched_on) DESC, words"))
      .limit(limit).pluck(:words, Arel.sql("SUM(count)"), Arel.sql("MAX(searched_on)"))
  end
end
