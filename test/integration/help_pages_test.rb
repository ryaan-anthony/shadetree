require "test_helper"

# OPS-06: the articles are public at /help (indexed, in the sitemap) and read by members in the
# app at /admin/help/articles (noindex, canonical to the public copy).
class HelpPagesTest < ActionDispatch::IntegrationTest
  SLUG = "get-help-from-shadetree"

  test "visitors read the public copy in the marketing layout, indexed" do
    get help_path
    assert_response :success
    assert_select "h1", "How can we help?"
    assert_select "#help-category-getting-started a[href='#{help_article_path(SLUG)}']", "Get help from the Shadetree team"
    assert_select "link[rel=canonical][href$='/help']"

    get help_article_path(SLUG)
    assert_response :success
    assert_select "h1", "Get help from the Shadetree team"
    assert_select "article.help-text h2.section-title", minimum: 1
    assert_select "meta[name=robots]", false
    assert_select "link[rel=canonical][href$='/help/#{SLUG}']"
    assert_select "main a[href='#{contact_path}']", "Contact us"
  end

  test "an unknown or malformed slug is not found" do
    get "/help/no-such-article"
    assert_response :not_found
    get "/help/..%2Fconfig"
    assert_response :not_found
  end

  test "signed-in members read the copy in the app, noindex, with the public copy as canonical" do
    sign_in users(:one)
    get "/help"
    assert_redirected_to admin_help_articles_path
    get "/help/#{SLUG}"
    assert_redirected_to admin_help_article_path(SLUG)
    follow_redirect!
    assert_response :success
    assert_select "meta[name=robots][content=noindex]"
    assert_select "link[rel=canonical][href='http://example.com/help/#{SLUG}']"
    assert_select "main article.help-text"
    assert_select "main a[href^='#{new_admin_support_ticket_path}']", "Ask Shadetree"

    get admin_support_tickets_path
    assert_response :success, "/admin/help stays the ticket list"
    assert_select "h1", "Help"
    get admin_help_articles_path
    assert_select "#help-category-getting-started a[href='#{admin_help_article_path(SLUG)}']"
  end

  test "a signed-in person with no business still reads the public copy" do
    user = User.create!(email: "nobiz@example.com", password: "password123", first_name: "No", last_name: "Biz", confirmed_at: Time.current)
    sign_in user
    get help_article_path(SLUG)
    assert_response :success
  end

  test "every member can read articles in the app" do
    sign_in member_with_role(:technician)
    get admin_help_article_path(SLUG)
    assert_response :success
  end

  test "the sitemap lists the help pages" do
    get sitemap_path
    assert_includes response.body, "/help</loc>"
    assert_includes response.body, "/help/#{SLUG}</loc>"
  end
end
