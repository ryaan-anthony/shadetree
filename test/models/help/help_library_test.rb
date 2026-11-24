require "test_helper"

# OPS-06: articles load from Markdown files with checked front matter, and their Markdown is
# rendered safely (raw HTML off, allowed links and images only, no style attributes).
class HelpLibraryTest < ActiveSupport::TestCase
  FRONT = { "title" => "Send a quote", "summary" => "Send it.", "category" => "quotes", "topics" => [ "send" ], "reviewed" => Date.new(2026, 11, 23) }.freeze

  setup { @dir = Pathname(Dir.mktmpdir).tap { _1.join("articles").mkpath } }
  teardown { FileUtils.rm_rf(@dir) }

  def write(slug, body = "Text.", **front)
    meta = FRONT.merge(front.transform_keys(&:to_s)).compact
    @dir.join("articles/#{slug}.md").write("#{meta.to_yaml}---\n#{body}\n")
  end

  def library = HelpCentre::Library.load(@dir)

  def render(body, front = {}, others: [])
    others.each { write(_1) }
    write("this", body, **front)
    lib = library
    markdown = HelpCentre::Markdown.new(lib.find("this"), lib, article_path: ->(slug) { "/help/#{slug}" }, image_path: ->(file) { "/assets/help/#{file}" })
    [ Nokogiri::HTML5.fragment(markdown.to_html), markdown.problems ]
  end

  test "an article's front matter and slug come from its file" do
    write("send-a-quote", "## Steps\n\nPress **Send**.")
    article = library.find("send-a-quote")
    assert_equal [ "Send a quote", "Send it.", "quotes", [ "send" ], Date.new(2026, 11, 23) ],
                 [ article.title, article.summary, article.category, article.topics, article.reviewed_on ]
    assert_equal "Quotes", article.category_name
    assert_equal "## Steps\n\nPress **Send**.", article.body
  end

  test "bad front matter fails loudly, naming the file" do
    { "wrong-category" => { category: "widgets" }, "no-title" => { title: "" }, "bad-date" => { reviewed: "soon" },
      "bad-topic" => { topics: [ "Send Page" ] }, "extra" => { author: "me" },
      "list-title" => { title: [ "Send", "a quote" ] }, "number-summary" => { summary: 42 },
      "bad-shot" => { screenshots: [ { "name" => "../etc", "path" => "/admin" } ] },
      "outside-shot" => { screenshots: [ { "name" => "x", "path" => "https://example.com/" } ] },
      "unused-record" => { screenshots: [ { "name" => "x", "path" => "/admin/quotes", "quote" => "Spring" } ] },
      "missing-record" => { screenshots: [ { "name" => "x", "path" => "/admin/quotes/:quote" } ] } }.each do |slug, front|
      FileUtils.rm_rf(@dir.join("articles").children)
      write(slug, **front)
      error = assert_raises(HelpCentre::InvalidArticle, slug) { library }
      assert_includes error.message, "#{slug}.md", slug
    end
    FileUtils.rm_rf(@dir.join("articles").children)
    @dir.join("articles/Not_A_Slug.md").write("---\ntitle: x\n---\n")
    assert_raises(HelpCentre::InvalidArticle) { library }
  end

  test "slugs are looked up in the index, never used as paths" do
    write("send-a-quote")
    lib = library
    assert lib.find("send-a-quote")
    [ "../send-a-quote", "send-a-quote.md", "SEND-A-QUOTE", nil, [ "send-a-quote" ], "" ].each { assert_nil lib.find(_1) }
  end

  test "raw HTML and style never reach the page, and raw HTML is reported" do
    html, problems = render(%(Hi <script>alert(1)</script> <b style="color:red">bold</b>\n\n<div onclick="x()">block</div>\n\n<style>p{}</style>))
    assert_empty html.css("script, style, div[onclick], b, [style]")
    assert_not_includes html.to_html, "raw HTML omitted"
    assert_includes html.text, "bold"
    assert_equal [ "this: has raw HTML, which isn't shown: use Markdown instead" ], problems
  end

  test "code blocks aren't highlighted (no inline styles)" do
    html, = render("```ruby\nx = 1\n```")
    assert_equal "x = 1\n", html.at_css("pre code").text
    assert_empty html.css("[style], span")
  end

  test "front matter that isn't keys and values fails, naming the file" do
    [ "- a list\n- of things", "just a sentence" ].each do |front|
      @dir.join("articles/odd.md").write("---\n#{front}\n---\nText.\n")
      error = assert_raises(HelpCentre::InvalidArticle) { library }
      assert_includes error.message, "odd.md"
    end
  end

  test "links: http(s), site paths, anchors and articles; anything else becomes text" do
    html, problems = render(<<~MD, others: %w[other-article])
      [web](https://example.com/a) [site](/pricing) [here](#steps) [article](other-article) [long](/help/other-article#x)
      [js](javascript:alert(1)) [data](data:text/html,x) [mail](mailto:someone@example.com) [proto](//evil.example/x) [gone](no-such-article)
    MD
    hrefs = html.css("a").map { _1["href"] }
    assert_equal [ "https://example.com/a", "/pricing", "#steps", "/help/other-article", "/help/other-article#x" ], hrefs
    assert_equal "noopener", html.at_css("a[href^=https]")["rel"]
    %w[js data mail proto gone].each { assert_includes html.text, _1 }
    assert_equal 5, problems.size, problems.inspect
  end

  test "images only from the help image folder, and declared screenshots as a picture" do
    shot = { "name" => "send-page", "path" => "/admin/quotes/:quote/send/new", "quote" => "Spring cleanup" }
    HelpCentre.image_root = @dir.join("images").tap(&:mkpath) # not the real folder: tests run in parallel
    files = HelpCentre::WIDTHS.map { HelpCentre.image_root.join("send-page-#{_1}.webp") }
    files.each { |file| Vips::Image.black(20, 10).webpsave(file.to_s) }
    html, problems = render(<<~MD, { screenshots: [ shot ] })
      ![Press Send quote](send-page)

      ![x](https://example.com/a.png) ![y](/etc/passwd) ![z](../send-page-1280.webp) ![](send-page)
    MD
    picture = html.at_css("figure.help-shot picture")
    assert_equal "/assets/help/send-page-390.webp", picture.at_css("source[media]")["srcset"]
    img = picture.at_css("img")
    assert_equal [ "/assets/help/send-page-1280.webp", "Press Send quote", "20", "10" ], [ img["src"], img["alt"], img["width"], img["height"] ]
    assert_nil html.at_css("p > figure"), "the figure replaces its paragraph"
    assert_equal 2, html.css("img").size, "only the screenshot, used twice"
    assert_equal 4, problems.size, problems.inspect # three outside the folder, one without alt text
  ensure
    HelpCentre.image_root = Rails.root.join("app/assets/images/help")
  end

  test "an uncaptured screenshot is left out and reported" do
    html, problems = render("![Press Send](later)", { screenshots: [ { "name" => "later", "path" => "/admin" } ] })
    assert_empty html.css("img")
    assert_match(/later hasn't been captured/, problems.join)
  end

  test "headings sit on the type scale under the page's H1, and tables scroll" do
    html, = render("# One\n\n## Two\n\n#### Four\n\n| a | b |\n|---|---|\n| 1 | 2 |")
    assert_equal [ %w[h2 section-title], %w[h2 section-title], %w[h3 card-title] ], html.css("h1, h2, h3, h4").map { [ _1.name, _1["class"] ] }
    assert html.at_css(".help-table > table")
  end

  test "sync copies the files into the table; only a full sync (at boot) deletes removed ones" do
    write("one")
    write("two")
    HelpArticle.sync!(library)
    assert_equal %w[one two], HelpArticle.order(:slug).pluck(:slug)
    assert HelpArticle.current?(library)

    write("one", "Changed text about invoices.")
    FileUtils.rm(@dir.join("articles/two.md"))
    assert_not HelpArticle.current?(library)
    HelpArticle.ensure_current!(library)
    assert_equal %w[one two], HelpArticle.order(:slug).pluck(:slug), "a page never deletes: an older server may still serve it"
    assert HelpArticle.current?(library)
    HelpArticle.sync!(library)
    assert_equal [ "one" ], HelpArticle.pluck(:slug)
    assert_includes HelpArticle.find_by!(slug: "one").body, "invoices"
    assert_no_changes(-> { HelpArticle.maximum(:updated_at) }) { HelpArticle.ensure_current!(library) }
  end

  test "boot syncs only in the web server, and a bad article never stops it starting" do
    write("one")
    HelpCentre.root = @dir
    HelpCentre.reset!
    HelpArticle.sync_at_boot
    assert_equal 0, HelpArticle.count, "not in a task or a test"
    program = $PROGRAM_NAME
    $PROGRAM_NAME = "puma: cluster worker 0"
    HelpArticle.sync_at_boot
    assert_equal [ "one" ], HelpArticle.pluck(:slug)
    @dir.join("articles/bad.md").write("---\ntitle: x\n---\n")
    HelpCentre.reset!
    assert_nothing_raised { HelpArticle.sync_at_boot }
  ensure
    $PROGRAM_NAME = program if program
    HelpCentre.root = Rails.root.join("content/help")
    HelpCentre.reset!
  end

  test "the repo's own articles load and render without problems" do
    lib = HelpCentre::Library.load(HelpCentre.root)
    assert lib.articles.any?
    lib.articles.each { |article| assert_includes HelpCentre::CATEGORIES.keys, article.category, article.slug }
  end
end
