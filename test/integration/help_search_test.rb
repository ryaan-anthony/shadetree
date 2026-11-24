require "test_helper"

# OPS-06: searching articles (both copies), the Help menu, suggestions on the ticket form and
# "Learn more" from the pages with a help topic.
class HelpSearchTest < ActionDispatch::IntegrationTest
  include HelpLibraryHelpers

  test "search matches titles and text, best first, with word prefixes" do
    HelpArticle.sync!
    assert_equal "your-business-settings", HelpArticle.search("settings").first.slug, "the title beats the summary and text"
    assert_equal %w[invoices-and-taxes take-tax-off-an-invoice].sort, HelpArticle.search("tax invoice").pluck(:slug).sort
    assert_includes HelpArticle.search("invoic").pluck(:slug), "take-tax-off-an-invoice"
    assert_equal [ "send-a-quote" ], HelpArticle.search("send quote email").pluck(:slug), "every word when some match all"
    assert_includes HelpArticle.search("quote zebra").pluck(:slug), "send-a-quote", "else any word"
    assert_empty HelpArticle.search("the and of")
    assert_nothing_raised { HelpArticle.search("'); drop table help_articles; -- :* & !").to_a }
    assert HelpArticle.exists?
    assert_empty HelpArticle.search("")
  end

  test "visitors search the public copy; no results suggests contacting us" do
    get help_path(q: "tax")
    assert_response :success
    assert_select "#help-results a[href='#{help_article_path("take-tax-off-an-invoice")}']"
    assert_select "meta[name=robots][content=noindex]", 1, "results pages aren't indexed"
    get help_path(q: "zebra crossing")
    assert_select "#help-no-results", /No articles for “zebra crossing”/
    assert_select "#help-no-results a[href='#{contact_path}']", "contact us"
    assert_select "form[role=search] input[type=search][name=q]"
  end

  test "members search in the app; no results offers Ask Shadetree" do
    sign_in users(:one)
    get help_path(q: "tax")
    assert_redirected_to admin_help_articles_path(q: "tax")
    follow_redirect!
    assert_select "turbo-frame#help_results #help-results a[href='#{admin_help_article_path("take-tax-off-an-invoice")}']"
    get admin_help_articles_path(q: "<b>zebra</b>")
    assert_select "#help-no-results .empty-title", "No articles for “<b>zebra</b>”"
    assert_equal new_admin_support_ticket_path(from: admin_help_articles_path), css_select("#help-no-results a.btn").first["href"]
  end

  test "the Help menu has a labelled search box and Help articles" do
    sign_in users(:one)
    get admin_root_path
    assert_select "#help-menu ~ .menu form[role=search][action='#{admin_help_articles_path}']" do
      assert_select "label[for=help-menu-q]", "Search help articles"
      assert_select "input#help-menu-q[type=search][name=q]"
    end
    assert_select "#help-menu ~ .menu a.menu-item[href='#{admin_help_articles_path}']", /Help articles/
  end

  test "the ticket form suggests articles for the page it came from, and for its subject" do
    sign_in users(:one)
    get new_admin_support_ticket_path(from: "/admin/schedule")
    assert_select "#help-suggestions a[href='#{admin_help_article_path("plan-your-week")}'][target=_blank]", /Plan your week/
    assert_select "form[data-controller=help-suggestions] input[name='support_ticket[subject]'][data-help-suggestions-target=subject]"

    post suggestions_admin_help_articles_path, params: { subject: "take tax off an invoice", page: "/admin/schedule" }, as: :turbo_stream
    assert_response :success
    links = Nokogiri::HTML5(response.body.gsub(%r{</?(turbo-stream|template)[^>]*>}, "")).css("#help-suggestions a").map { _1["href"] }
    assert_equal admin_help_article_path("plan-your-week"), links.first, "the page's articles first"
    assert_includes links, admin_help_article_path("take-tax-off-an-invoice")
    assert_operator links.size, :<=, 3

    post suggestions_admin_help_articles_path, params: { subject: "", page: "https://evil.example/admin" }, as: :turbo_stream
    assert_select "#help-suggestions a", false
  end

  test "a question shown again after a mistake keeps its suggestions, and still sends" do
    sign_in users(:one)
    post admin_support_tickets_path, params: { support_ticket: { subject: "Send a quote", category: "question", page: "/admin/quotes", body: "" } }
    assert_response :unprocessable_content
    assert_select "#help-suggestions a[href='#{admin_help_article_path("send-a-quote")}']"
    post admin_support_tickets_path, params: { support_ticket: { subject: "Send a quote", category: "question", page: "/admin/quotes", body: "How?" } }
    assert_redirected_to %r{/admin/help/\w+}
  end

  test "Learn more links each page to its topic's article; only the send page opens a new tab" do
    pages = StaffPages.build(businesses(:one), users(:one))
    sign_in users(:one)
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    get StaffPages.find(pages, :send_quote).path # a message being written stays
    assert_select ".page-head a.help-learn-more[href='#{admin_help_article_path("send-a-quote")}'][target=_blank]", 1 do
      assert_select ".sr-only", /opens in a new tab/
    end
    { settings_business: "your-business-settings", schedule: "plan-your-week" }.each do |key, slug|
      get StaffPages.find(pages, key).path
      assert_select ".page-head a.help-learn-more[href='#{admin_help_article_path(slug)}']:not([target])", 1, key.to_s
      assert_select ".page-head a.help-learn-more .sr-only", text: /new tab/, count: 0
    end
  end

  test "a first-time tip links to its topic's article" do
    sign_in users(:one)
    get admin_catalog_items_path
    assert_select ".tip a.help-learn-more[href='#{admin_help_article_path("invoices-and-taxes")}']"
  end

  test "an undeclared topic fails loudly" do
    error = assert_raises(ArgumentError) { ActionView::Base.empty.extend(HelpHelper).learn_more(:no_such_topic) }
    assert_includes error.message, "content/help/topics.yml"
  end
end
