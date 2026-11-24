# OPS-06: help articles in the page: their HTML for this copy (public or in the app), and the
# address of an article in the copy the reader is in.
module HelpHelper
  def help_in_app? = controller_path.start_with?("admin/")

  def help_path_for(slug) = help_in_app? ? admin_help_article_path(slug) : help_article_path(slug)
  def help_home_path = help_in_app? ? admin_help_articles_path : help_path

  # Rendered once per article file, copy and set of articles, in this process (asset addresses
  # change with each deploy, so not in the shared cache).
  HTML = Concurrent::Map.new

  def help_article_html(article)
    render = -> { HelpCentre::Markdown.new(article, help_library, article_path: method(:help_path_for), image_path: ->(file) { image_path("help/#{file}") }).to_html }
    return render.call if Rails.env.development? # pictures captured while it runs show at once

    HTML.compute_if_absent([ article.digest, help_in_app?, help_library.slugs.hash ], &render)
  end

  # The public address of an article, for the in-app copy's canonical link.
  def help_public_url(article) = "#{public_base_url}#{help_article_path(article.slug)}"
end
