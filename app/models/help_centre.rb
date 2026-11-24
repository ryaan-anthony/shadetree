# OPS-06: the help centre's articles. Each is a Markdown file in content/help/articles, named by
# its slug, with front matter:
#
#   ---
#   title: Send a quote by text
#   summary: Text your client a link to the quote, and see when they open it.
#   category: quotes                 # a key of CATEGORIES
#   topics: [send]                   # the help topics it explains (content/help/topics.yml)
#   reviewed: 2026-11-23             # when it was last checked against the screens
#   screenshots:                     # the pictures it shows (HelpScreenshots captures them)
#     - name: send-quote
#       path: /admin/quotes/:quote/send/new
#       quote: Spring cleanup
#   ---
#
# The files go live with the deploy: HelpArticle.sync! copies them into a table at boot for
# search and counts. Slugs come from this index, never from a request's path.
#
#   HelpCentre.library.find("send-a-quote")   # => HelpCentre::Article, or nil
#   HelpCentre.library.in_category("quotes")
module HelpCentre
  class InvalidArticle < StandardError; end

  # The categories, in the order they're browsed (owner, 2026-11-23).
  CATEGORIES = {
    "getting-started" => "Getting started",
    "clients-requests" => "Clients & requests",
    "quotes" => "Quotes",
    "schedule-jobs" => "Schedule & jobs",
    "invoices-payments" => "Invoices & payments",
    "services-prices" => "Services & prices",
    "settings-team" => "Settings & team",
    "plan-billing" => "Plan & billing"
  }.freeze
  CATEGORY_SUMMARIES = {
    "getting-started" => "Set up your business and find your way around.",
    "clients-requests" => "Add clients, take requests and follow them up.",
    "quotes" => "Build, send and revise quotes, and see what your client sees.",
    "schedule-jobs" => "Plan the work, book visits and run the day, including My day.",
    "invoices-payments" => "Bill the work, take payments and fix mistakes.",
    "services-prices" => "Your services, prices, taxes and locations.",
    "settings-team" => "Your business details, messages, automations and team.",
    "plan-billing" => "Your Shadetree plan, limits and billing."
  }.freeze

  SLUG = /\A[a-z0-9-]+\z/
  TOPIC = /\A[a-z0-9_]+\z/
  FIELDS = %w[title summary category topics reviewed screenshots].freeze
  SCREENSHOT_FIELDS = %w[name path as region scroll].freeze
  # Placeholders a screenshot's path may use, each filled from a demo record named in the same
  # entry (`quote: Spring cleanup`): see HelpScreenshots::RECORDS.
  PLACEHOLDER = /:([a-z_]+)/

  Screenshot = Data.define(:name, :path, :as, :region, :scroll, :records) do
    def files = HelpCentre::WIDTHS.map { "#{name}-#{_1}.webp" }
  end

  Article = Data.define(:slug, :title, :summary, :category, :topics, :reviewed_on, :screenshots, :body, :digest) do
    def category_name = HelpCentre::CATEGORIES.fetch(category)
    def screenshot(name) = screenshots.find { _1.name == name }
  end

  # Screenshots are captured at these widths (desktop and phone) and stored as WebP.
  WIDTHS = [ 1280, 390 ].freeze

  mattr_accessor :root, default: Rails.root.join("content/help")

  def self.image_root = Rails.root.join("app/assets/images/help")

  # The articles, loaded once; in development, again whenever a file changes.
  def self.library
    stamp = Rails.env.development? ? Dir[root.join("articles/*.md")].sort.map { [ _1, File.mtime(_1) ] } : nil
    @library = nil if stamp != @stamp || @library&.root != root
    @stamp = stamp
    @library ||= Library.load(root)
  end

  def self.reset! = @library = nil

  class Library
    attr_reader :root, :articles

    def self.load(root)
      new(root, Dir[Pathname(root).join("articles/*.md")].sort.map { parse(_1) })
    end

    def initialize(root, articles)
      @root = Pathname(root)
      @articles = articles.freeze
      @by_slug = articles.index_by(&:slug).freeze
    end

    def find(slug) = (@by_slug[slug] if slug.is_a?(String) && slug.match?(SLUG))
    def slugs = @by_slug.keys
    def in_category(key) = articles.select { _1.category == key }.sort_by(&:title)
    def for_topic(topic) = articles.select { _1.topics.include?(topic.to_s) }

    def self.parse(file)
      slug = File.basename(file, ".md")
      fail_with(file, "its name isn't a slug (a-z, 0-9 and hyphens)") unless slug.match?(SLUG)
      text = File.read(file, encoding: "UTF-8")
      match = text.match(/\A---\n(.*?)\n---\n(.*)\z/m) || fail_with(file, "it has no front matter")
      meta = YAML.safe_load(match[1], permitted_classes: [ Date ]) || {}
      fail_with(file, "its front matter must be keys and values (title:, summary: …)") unless meta.is_a?(Hash)
      check(file, meta)
      Article.new(slug:, title: meta["title"].strip, summary: meta["summary"].strip, category: meta["category"],
                  topics: Array(meta["topics"]).map(&:to_s).freeze, reviewed_on: meta["reviewed"],
                  screenshots: Array(meta["screenshots"]).map { screenshot(file, _1) }.freeze,
                  body: match[2].strip, digest: Digest::SHA256.hexdigest(text))
    rescue Psych::Exception => error
      fail_with(file, "its front matter isn't valid YAML (#{error.message})")
    end

    def self.check(file, meta)
      fail_with(file, "unknown front matter #{(meta.keys - FIELDS).join(", ")}") if (meta.keys - FIELDS).any?
      %w[title summary].each { fail_with(file, "#{_1} is missing") if meta[_1].to_s.strip.empty? }
      fail_with(file, "category #{meta["category"].inspect} isn't one of #{CATEGORIES.keys.join(", ")}") unless CATEGORIES.key?(meta["category"])
      fail_with(file, "topics must be a list of topic keys") unless Array(meta["topics"]).all? { _1.to_s.match?(TOPIC) }
      fail_with(file, "reviewed must be a date (YYYY-MM-DD)") unless meta["reviewed"].is_a?(Date)
    end

    def self.screenshot(file, entry)
      fail_with(file, "each screenshot needs a name and a path") unless entry.is_a?(Hash) && entry["name"] && entry["path"]
      name, path = entry["name"].to_s, entry["path"].to_s
      fail_with(file, "screenshot name #{name.inspect} isn't a slug") unless name.match?(SLUG)
      fail_with(file, "screenshot #{name}'s path must be a staff page (/admin…)") unless path.match?(%r{\A/admin(/[a-z0-9_:\-/]*)?(\?[a-z0-9_=&\-]*)?\z})
      records = entry.except(*SCREENSHOT_FIELDS)
      wanted = path.scan(PLACEHOLDER).flatten
      fail_with(file, "screenshot #{name} names #{(records.keys - wanted).join(", ")}, which its path doesn't use") if (records.keys - wanted).any?
      fail_with(file, "screenshot #{name}'s path needs #{(wanted - records.keys).join(", ")}") if (wanted - records.keys).any?
      as = entry.fetch("as", "owner").to_s
      fail_with(file, "screenshot #{name}: as must be owner, admin or technician") unless %w[owner admin technician].include?(as)
      Screenshot.new(name:, path:, as:, region: entry.fetch("region", "main").to_s, scroll: entry["scroll"]&.to_s,
                     records: records.transform_values(&:to_s).freeze)
    end

    def self.fail_with(file, problem) = raise(InvalidArticle, "#{Pathname(file).basename}: #{problem}")
  end
end
