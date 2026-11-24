# OPS-06: an article's Markdown as safe HTML. Commonmarker (GitHub-flavoured, raw HTML off)
# renders it; then every link and image is checked against the allow list:
#
# - links: http(s), "#anchors", and paths on this site ("/pricing"). Another article is linked
#   by its slug ("send-a-quote", or "/help/send-a-quote") and gets the copy's address (public or
#   in the app); a link to an article that doesn't exist, or any other scheme, becomes plain text.
# - images: only from the help image folder: a screenshot the article declares ("send-quote",
#   shown at the phone or the desktop width) or a file there ("arrow.webp"). Others are dropped.
# - no style, class or id from the source (the CSP allows only our stylesheets); headings get
#   the kit's type-scale classes and a page's only H1 stays its title.
#
#   HelpCentre::Markdown.new(article, library, article_path: ->(slug) { help_article_path(slug) },
#                            image_path: ->(file) { image_path("help/#{file}") }).to_html
class HelpCentre::Markdown
  OPTIONS = { render: { unsafe: false, hardbreaks: false }, parse: { smart: true },
              extension: { table: true, strikethrough: true, autolink: true, tagfilter: true, tasklist: false, header_ids: nil, footnotes: false } }.freeze
  ARTICLE_LINK = %r{\A(?:/help/)?([a-z0-9-]+)(#[a-z0-9-]+)?\z}
  SITE_PATH = %r{\A/(?!/)[^\s\\]*\z}
  IMAGE_FILE = /\A[a-z0-9-]+\.webp\z/
  HEADINGS = { "h1" => "h2", "h2" => "h2", "h3" => "h3", "h4" => "h3", "h5" => "h3", "h6" => "h3" }.freeze
  HEADING_CLASS = { "h2" => "section-title", "h3" => "card-title" }.freeze

  # Problems found while rendering (a link to a missing article, an image that isn't allowed),
  # for the link check (HelpChecks); rendering itself never fails on them.
  attr_reader :problems

  def initialize(article, library, article_path:, image_path:)
    @article = article
    @library = library
    @article_path = article_path
    @image_path = image_path
    @problems = []
  end

  def to_html
    doc = Nokogiri::HTML5.fragment(Commonmarker.to_html(@article.body, options: OPTIONS))
    doc.xpath(".//comment()").each(&:remove) # "raw HTML omitted"
    doc.css("*").each { |node| %w[style class id].each { node.remove_attribute(_1) } }
    doc.css("a").each { link(_1) }
    doc.css("img").each { image(_1) }
    doc.css("h1, h2, h3, h4, h5, h6").each { heading(_1) }
    doc.css("table").each { _1.wrap(%(<div class="help-table"></div>)) }
    doc.to_html.html_safe # rubocop:disable Rails/OutputSafety -- built from Commonmarker's escaped output, checked above
  end

  private

  def link(node)
    href = node["href"].to_s
    if (match = href.match(ARTICLE_LINK))
      return node["href"] = "#{@article_path.call(match[1])}#{match[2]}" if @library.find(match[1])

      problem("links to #{href.inspect}, which isn't an article")
    elsif href.start_with?("#") || href.match?(SITE_PATH)
      return
    elsif href.match?(%r{\Ahttps?://[^\s]+\z}i)
      return node["rel"] = "noopener"
    else
      problem("links to #{href.inspect}: only http(s), site paths and articles")
    end
    node.replace(node.children)
  end

  def image(node)
    src = node["src"].to_s
    alt = node["alt"].to_s
    # A picture on its own line is the paragraph's only content: the figure takes the paragraph's place.
    alone = node.parent&.name == "p" && node.parent.children.all? { _1 == node || (_1.text? && _1.text.strip.empty?) }
    target = alone ? node.parent : node
    problem("an image without alt text (#{src})") if alt.blank?
    if (shot = @article.screenshot(src))
      files = shot.files.map { HelpCentre.image_root.join(_1) }
      return target.replace(picture(shot, alt)) if files.all?(&:exist?)

      problem("screenshot #{src} hasn't been captured (#{shot.files.join(", ")})")
    elsif src.match?(IMAGE_FILE) && HelpCentre.image_root.join(src).exist?
      return target.replace(%(<figure class="help-shot"><img src="#{ERB::Util.h(@image_path.call(src))}" alt="#{ERB::Util.h(alt)}" loading="lazy"></figure>))
    else
      problem("an image from outside the help image folder, or missing: #{src.inspect}")
    end
    target.remove
  end

  # The phone capture on narrow screens, the desktop one elsewhere.
  def picture(shot, alt)
    desktop, phone = shot.files
    width, height = HelpCentre::ImageSize.of(HelpCentre.image_root.join(desktop))
    <<~HTML.squish
      <figure class="help-shot"><picture>
      <source media="(max-width: 40rem)" srcset="#{ERB::Util.h(@image_path.call(phone))}">
      <img src="#{ERB::Util.h(@image_path.call(desktop))}" alt="#{ERB::Util.h(alt)}" width="#{width}" height="#{height}" loading="lazy">
      </picture></figure>
    HTML
  end

  def heading(node)
    node.name = HEADINGS.fetch(node.name)
    node["class"] = HEADING_CLASS.fetch(node.name)
  end

  def problem(text) = @problems << "#{@article.slug}: #{text}"
end
