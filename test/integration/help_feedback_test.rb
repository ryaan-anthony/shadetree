require "test_helper"

# OPS-06: "Was this helpful?" counts and no-result search counts: nothing about who, words only,
# rate limited, kept 90 days, escaped in the operators' list.
class HelpFeedbackTest < ActionDispatch::IntegrationTest
  include HelpLibraryHelpers
  include OperatorHelpers

  SLUG = "send-a-quote"

  def over_the_limit
    store = ActionController::Base.cache_store
    store.define_singleton_method(:increment) { |*, **| 10_000 }
    yield
  ensure
    store.singleton_class.remove_method(:increment)
  end

  def counts = HelpArticle.find_by!(slug: SLUG).then { [ _1.helpful_count, _1.unhelpful_count ] }

  test "visitors vote; a no offers Contact us" do
    get help_article_path(SLUG)
    assert_select "#help-vote form[action='#{help_article_vote_path(SLUG)}'] button", "Yes"
    post help_article_vote_path(SLUG), params: { helpful: "yes" }, as: :turbo_stream
    assert_select "turbo-stream[action=replace][target=help-vote]"
    assert_includes response.body, "Glad it helped"
    post help_article_vote_path(SLUG), params: { helpful: "no" }
    assert_redirected_to help_article_path(SLUG, voted: "no") + "#help-vote"
    follow_redirect!
    assert_select "#help-vote a[href='#{contact_path}']", "Contact us"
    assert_equal [ 1, 1 ], counts
  end

  test "members vote in the app; a no offers Ask Shadetree" do
    sign_in users(:one)
    post vote_admin_help_article_path(SLUG), params: { helpful: "no" }, as: :turbo_stream
    assert_includes response.body, %(href="#{new_admin_support_ticket_path(from: admin_help_article_path(SLUG)).gsub("&", "&amp;")}")
    assert_equal [ 0, 1 ], counts
    get help_article_path(SLUG)
    assert_redirected_to admin_help_article_path(SLUG)
  end

  test "votes over the limit get the same thanks, uncounted" do
    get help_article_path(SLUG)
    over_the_limit { post help_article_vote_path(SLUG), params: { helpful: "no" }, as: :turbo_stream }
    assert_response :success
    assert_includes response.body, "Thanks for telling us"
    assert_equal [ 0, 0 ], counts
  end

  test "a search with no results is counted by its words only" do
    get help_path(q: "Refund maria@example.com 555-380-3141 Zebra!")
    get help_path(q: "refund   zebra")
    get help_path(q: "send") # found: not counted
    assert_equal [ [ "refund zebra", 2 ] ], HelpSearchMiss.pluck(:words, :count)
    get help_path(q: "555 380 3141")
    get help_path(q: "x@y.example")
    assert_equal 1, HelpSearchMiss.count, "nothing left to count"
  end

  test "typing in the app's list isn't counted; the Help menu's search is" do
    sign_in users(:one)
    get admin_help_articles_path(q: "zebr"), headers: { "Turbo-Frame" => "help_results" }
    assert_equal 0, HelpSearchMiss.count
    get admin_help_articles_path(q: "zebra")
    assert_equal [ "zebra" ], HelpSearchMiss.pluck(:words)
  end

  test "no-result counts are rate limited per address" do
    over_the_limit { get help_path(q: "zebra") }
    assert_response :success
    assert_equal 0, HelpSearchMiss.count
  end

  test "words are at most 100 characters, and kept 90 days" do
    assert_operator HelpSearchMiss.words("tree " * 40).length, :<=, 100
    assert_nil HelpSearchMiss.words("12345 +1 (555) 380-3141")
    HelpSearchMiss.record("old words", on: Date.current - 91)
    HelpSearchMiss.record("new words")
    PruneHelpSearchMissesJob.perform_now
    assert_equal [ "new words" ], HelpSearchMiss.pluck(:words)
  end

  test "operators see the counts, escaped" do
    HelpSearchMiss.record("script alert")
    HelpSearchMiss.create!(words: "<script>alert(1)</script>", searched_on: Date.current)
    HelpArticle.sync!
    HelpArticle.where(slug: SLUG).update_all(helpful_count: 2, unhelpful_count: 5)
    sign_in_operator(users(:one))
    get ops_help_path
    assert_response :success
    assert_select "#help-misses td", "script alert"
    assert_select "#help-misses td", "<script>alert(1)</script>"
    assert_not_includes response.body, "<script>alert(1)"
    assert_select "#help-votes tr", /Send a quote\s*2\s*5/
  end

  test "members can't open the operators' list" do
    sign_in users(:one)
    get ops_help_path
    assert_response :not_found
  end
end
