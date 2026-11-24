# OPS-06: what keeps the help articles in step with the app, checked in CI (test/models/help/
# help_checks_test.rb; the screenshots' digests by bin/help-screenshots --check):
#
# - every help topic a page uses (`learn_more(:topic)`, and each first-time tip's) is declared
#   in content/help/topics.yml, and every topic an article lists is too;
# - every link in an article goes to an article that exists, and every image to a file in the
#   help image folder; each declared screenshot is shown, captured, and none is left over;
# - an article was re-read (its reviewed date) on or after its screenshots were last captured;
# - no other company's product name appears in an article's words or alt text (HelpCentre::BRANDS).
#
#   HelpCentre::Checks.problems  # => ["send-a-quote: links to \"old-slug\", which isn't an article", …]
module HelpCentre::Checks
  SOURCES = %w[app/views/**/*.erb app/helpers/**/*.rb app/controllers/**/*.rb].freeze
  USE = /\blearn_more[\s(]+[:"']([a-z0-9_]+)/
  IMAGE = /!\[[^\]]*\]\(([^)\s]+)/

  extend self

  def problems(library = HelpCentre.library)
    undeclared_topics(library) + links(library) + screenshots(library) + reviews(library) + brands(library)
  end

  # [topic, where] for each help topic the app's pages use.
  def topics_used
    used = SOURCES.flat_map { Dir[Rails.root.join(_1)] }.sort.flat_map do |file|
      File.read(file).scan(USE).flatten.map { [ _1, Pathname(file).relative_path_from(Rails.root).to_s ] }
    end
    used + FirstTimeTips::KEYS.map { [ _1, "a first-time tip (FirstTimeTips)" ] }
  end

  def undeclared_topics(library)
    declared = HelpCentre.topics.keys
    topics_used.reject { declared.include?(_1.first) }.map { |topic, where| "#{where} uses the help topic #{topic.inspect}, which content/help/topics.yml doesn't declare" } +
      library.articles.flat_map { |article| (article.topics - declared).map { "#{article.slug}: lists the help topic #{_1.inspect}, which content/help/topics.yml doesn't declare" } }
  end

  # Topics with no article: "Learn more" would show nothing.
  def uncovered_topics(library)
    (HelpCentre.topics.keys - library.articles.flat_map(&:topics)).map { "The help topic #{_1.inspect} has no article: write one that lists it under topics" }
  end

  def links(library)
    library.articles.flat_map do |article|
      HelpCentre::Markdown.new(article, library, article_path: ->(slug) { "/help/#{slug}" }, image_path: ->(file) { file }).tap(&:to_html).problems
    end
  end

  def screenshots(library)
    declared = library.articles.flat_map(&:screenshots)
    problems = library.articles.flat_map do |article|
      shown = article.body.scan(IMAGE).flatten
      article.screenshots.reject { shown.include?(_1.name) }.map { "#{article.slug}: declares the screenshot #{_1.name} but doesn't show it" }
    end
    problems += declared.group_by(&:name).select { _2.size > 1 }.keys.map { "The screenshot #{_1} is declared more than once" }
    files = declared.flat_map(&:files)
    used = library.articles.flat_map { _1.body.scan(IMAGE).flatten }.grep(HelpCentre::Markdown::IMAGE_FILE)
    leftovers = Dir[HelpCentre.image_root.join("*")].map { File.basename(_1) } - files - used
    problems + leftovers.map { "app/assets/images/help/#{_1} isn't used by any article: delete it" }
  end

  def brands(library)
    library.articles.flat_map do |article|
      [ article.title, article.summary, article.body ].join("\n").scan(HelpCentre::BRANDS).uniq.map { "#{article.slug}: names #{_1}; say what it does instead" }
    end
  end

  def reviews(library)
    recorded = HelpCentre::Screenshots.recorded
    library.articles.filter_map do |article|
      captured = article.screenshots.filter_map { recorded.dig(_1.name, "captured_on")&.then { |date| Date.parse(date.to_s) } }.max
      next unless captured && article.reviewed_on < captured

      "#{article.slug}: its screenshots were captured on #{captured}; re-read it and set reviewed to that date or later"
    end
  end
end
