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
#     - name: send-quote               # its files: send-quote-1280.webp and send-quote-390.webp
#       path: /admin/quotes/:quote/send/new
#       quote: Spring cleanup          # the demo record for :quote (HelpCentre::Screenshots::RECORDS)
#       region: "#send-form"           # what's captured (default: main)
#       as: owner                      # who's signed in: owner (default), admin, technician, or
#                                      # new (the owner of the new, empty demo business)
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
  # Articles (their words and alt text) don't name other companies' products: say what a thing
  # does ("your card payment provider"), not whose it is. The app's own wording, and so the
  # screenshots of it, stay as they are (spec Decisions, 2026-11-24). Case-sensitive, whole
  # words: "apple trees" and "chrome trim" are fine.
  BRANDS = /\b(?:Stripe|WhatsApp|Apple\s+Pay|Google\s+Pay|Google|PayPal|Venmo|Zelle|Gmail|Outlook|iPhone|Android|Chrome|Safari|Microsoft|Excel|QuickBooks|Facebook|Instagram|Mastercard|Visa)\b/
  TOPIC = /\A[a-z0-9_]+\z/
  FIELDS = %w[title summary category topics reviewed screenshots].freeze
  SCREENSHOT_FIELDS = %w[name path as region].freeze
  # Placeholders a screenshot's path may use, each filled from a demo record named in the same
  # entry (`quote: Spring cleanup`): see HelpScreenshots::RECORDS.
  PLACEHOLDER = /:([a-z_]+)/

  Screenshot = Data.define(:name, :path, :as, :region, :records) do
    def files = HelpCentre::WIDTHS.map { "#{name}-#{_1}.webp" }
  end

  Article = Data.define(:slug, :title, :summary, :category, :topics, :reviewed_on, :screenshots, :body, :digest) do
    def category_name = HelpCentre::CATEGORIES.fetch(category)
    def screenshot(name) = screenshots.find { _1.name == name }
  end

  # Screenshots are captured at these widths (desktop and phone) and stored as WebP.
  WIDTHS = [ 1280, 390 ].freeze

  mattr_accessor :root, default: Rails.root.join("content/help")

  mattr_accessor :image_root, default: Rails.root.join("app/assets/images/help")

  # The articles, loaded once; in development, again whenever a file changes.
  def self.library
    stamp = Rails.env.development? ? Dir[root.join("articles/*.md")].sort.map { [ _1, File.mtime(_1) ] } : nil
    @library = nil if stamp != @stamp || @library&.root != root
    @stamp = stamp
    @library ||= Library.load(root)
  end

  def self.reset! = @library = @topics = nil

  # The declared help topics: { "send" => ["admin/quote_sends#new"], … } (content/help/topics.yml).
  def self.topics
    @topics = nil if Rails.env.development?
    @topics ||= YAML.safe_load_file(root.join("topics.yml")).to_h { |key, value| [ key, Array(value&.dig("pages")).freeze ] }.freeze
  end

  def self.topic!(key)
    key = key.to_s
    topics.key?(key) ? key : raise(ArgumentError, "Undeclared help topic #{key.inspect}: add it to content/help/topics.yml")
  end

  # Up to three articles for a question about to be sent: those about the page it was sent
  # from (the ticket's page, a path in the app), then the best matches for its subject.
  def self.suggestions(subject:, page:, limit: 3)
    HelpArticle.ensure_current!(library)
    by_page = topics_for_page(page).flat_map { library.for_topic(_1) }
    by_subject = HelpArticle.search(subject).limit(limit).pluck(:slug).filter_map { library.find(_1) }
    (by_page + by_subject).uniq(&:slug).first(limit)
  end

  def self.topics_for_page(page)
    path = page.to_s
    return [] unless path.start_with?("/admin")

    route = Rails.application.routes.recognize_path(path)
    screen = "#{route[:controller]}##{route[:action]}"
    topics.select { |_, pages| pages.include?(screen) }.keys
  rescue ActionController::RoutingError
    []
  end

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
      %w[title summary].each do |key|
        fail_with(file, "#{key} must be text") unless meta[key].nil? || meta[key].is_a?(String)
        fail_with(file, "#{key} is missing") if meta[key].to_s.strip.empty?
      end
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
      fail_with(file, "screenshot #{name}: as must be #{HelpCentre::Screenshots::USERS.keys.join(", ")}") unless HelpCentre::Screenshots::USERS.key?(as)
      Screenshot.new(name:, path:, as:, region: entry.fetch("region", "main").to_s,
                     records: records.transform_values(&:to_s).freeze)
    end

    def self.fail_with(file, problem) = raise(InvalidArticle, "#{Pathname(file).basename}: #{problem}")
  end
end
