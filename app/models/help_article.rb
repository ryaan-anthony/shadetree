# OPS-06: a help article as stored for search (and, from part 3, its "Was this helpful?" counts).
# The files in content/help/articles are the source (HelpCentre); sync! copies them here at boot,
# deleting removed ones. A help page that finds the table behind its files only adds and
# updates: during a deploy the old and new servers run side by side, and neither may delete the
# other's articles (and their counts). Rows for removed files go at the next boot, and pages
# never show them (they're looked up in the loaded files).
class HelpArticle < ApplicationRecord
  CONTENT = %i[title summary category topics body digest].freeze

  # Idempotent: adds new articles and rewrites changed ones; with delete: true (at boot), also
  # deletes removed ones.
  def self.sync!(library = HelpCentre.library, delete: true)
    rows = library.articles.map { |article| { slug: article.slug, **CONTENT.to_h { [ _1, article.public_send(_1) ] } } }
    transaction do
      where.not(slug: rows.pluck(:slug)).delete_all if delete
      upsert_all(rows, unique_by: :slug, update_only: CONTENT) if rows.any?
    end
  end

  # Articles matching every word (from three letters, as prefixes: "invoic" finds "invoices"), best first, the
  # title counting most; when none match every word, those matching any.
  def self.search(query)
    words = query.to_s.downcase.scan(/[[:alnum:]]+/).uniq.first(12)
    words = connection.select_values(sanitize_sql_array([ "SELECT w FROM unnest(ARRAY[?]::text[]) AS w WHERE to_tsvector('english', w) <> ''::tsvector", words ])) if words.any? # no "the", "and"
    return none if words.empty?

    [ " & ", " | " ].each do |joiner|
      tsquery = words.map { _1.length >= 3 ? "#{_1}:*" : _1 }.join(joiner)
      matches = where("searchable @@ to_tsquery('english', ?)", tsquery)
      return matches.order(Arel.sql(sanitize_sql_array([ "ts_rank(searchable, to_tsquery('english', ?)) DESC, title", tsquery ]))) if matches.exists?
    end
    none
  end

  # Whether every loaded article is in the table as it is in its file.
  def self.current?(library = HelpCentre.library) = (library.articles.map { [ _1.slug, _1.digest ] } - pluck(:slug, :digest)).empty?
  def self.ensure_current!(library = HelpCentre.library) = (sync!(library, delete: false) unless current?(library))

  # At boot, in the web server only (`rails server`, or Puma as the image runs it): tasks and
  # the asset build may run without the database. Never stops the server from starting: a help
  # page syncs again before it's shown.
  def self.sync_at_boot
    return unless defined?(Rails::Server) || File.basename($PROGRAM_NAME).start_with?("puma")

    Rails.application.executor.wrap { sync! }
  rescue ActiveRecord::ActiveRecordError, HelpCentre::InvalidArticle => error
    Rails.logger.warn("[help] articles not synced at boot: #{error.class}")
  end
end
