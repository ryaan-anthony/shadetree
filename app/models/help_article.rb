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

  # Whether every loaded article is in the table as it is in its file.
  def self.current?(library = HelpCentre.library) = (library.articles.map { [ _1.slug, _1.digest ] } - pluck(:slug, :digest)).empty?
  def self.ensure_current!(library = HelpCentre.library) = (sync!(library, delete: false) unless current?(library))

  # At boot, in the web server only: tasks and the asset build may run without the database.
  def self.sync_at_boot
    return unless defined?(Rails::Server) || defined?(::Puma::Server)

    Rails.application.executor.wrap { sync! }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("[help] articles not synced at boot: #{error.class}")
  end
end
