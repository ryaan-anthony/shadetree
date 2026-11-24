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

  # "Learn more" to the article for a help topic (content/help/topics.yml). In the same tab (the
  # installed app opens new tabs in a browser that isn't signed in); new_tab: true where the page
  # holds something being typed, so it isn't lost. Nothing until the topic has an article; an
  # undeclared topic raises.
  def learn_more(topic, new_tab: false, **attributes)
    topic = HelpCentre.topic!(topic)
    articles = HelpCentre.library.for_topic(topic)
    article = articles.find { _1.topics.first == topic } || articles.first
    return unless article

    # A new tab may open in a browser that isn't signed in (the installed app's do): the public copy
    # reads anywhere, and a signed-in member there is sent on to the copy in the app.
    link_to (new_tab ? help_article_path(article.slug) : admin_help_article_path(article.slug)), target: ("_blank" if new_tab), rel: ("noopener" if new_tab), data: { help_topic: topic },
            class: [ "help-learn-more", attributes.delete(:class) ].compact.join(" "), **attributes do
      safe_join([ "Learn more", tag.span(": #{article.title}#{" (opens in a new tab)" if new_tab}", class: "sr-only") ])
    end
  end

  # The public address of an article, for the in-app copy's canonical link.
  def help_public_url(article) = "#{public_base_url}#{help_article_path(article.slug)}"
end
