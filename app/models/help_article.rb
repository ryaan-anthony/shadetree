# OPS-06: a help article as stored for search (and, from part 3, its "Was this helpful?" counts).
# The files in content/help/articles are the source (HelpCentre); sync! copies them here at boot
# and whenever a help page finds the table behind the files, so a deploy publishes them.
class HelpArticle < ApplicationRecord
  CONTENT = %i[title summary category topics body digest].freeze

  # Idempotent: adds new articles, rewrites changed ones and deletes removed ones.
  def self.sync!(library = HelpCentre.library)
    rows = library.articles.map { |article| { slug: article.slug, **CONTENT.to_h { [ _1, article.public_send(_1) ] } } }
    transaction do
      where.not(slug: rows.pluck(:slug)).delete_all
      upsert_all(rows, unique_by: :slug, update_only: CONTENT) if rows.any?
    end
  end

  def self.current?(library = HelpCentre.library) = pluck(:slug, :digest).sort == library.articles.map { [ _1.slug, _1.digest ] }.sort
  def self.ensure_current!(library = HelpCentre.library) = (sync!(library) unless current?(library))

  # At boot, in the web server only: tasks and the asset build may run without the database.
  def self.sync_at_boot
    return unless defined?(Rails::Server) || defined?(::Puma::Server)

    Rails.application.executor.wrap { sync! }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("[help] articles not synced at boot: #{error.class}")
  end
end
