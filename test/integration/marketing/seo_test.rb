require "test_helper"

# MKT-04: titles, descriptions, canonical addresses and link previews on public pages; the
# sitemap and robots rules; private surfaces kept out of search engines.
class MarketingSeoTest < ActionDispatch::IntegrationTest
  PAGES = %i[root_path features_path pricing_path about_path contact_path terms_path privacy_path].freeze

  test "every marketing page has its own title and description, a canonical address and a share card" do
    seen = PAGES.map do |page|
      get public_send(page)
      assert_response :success
      title = css_select("title").first.text
      description = css_select("meta[name=description]").first["content"]
      assert_select "link[rel=canonical][href=?]", "http://example.com#{public_send(page)}"
      assert_select "meta[property='og:title'][content=?]", title
      assert_select "meta[property='og:image'][content*='/assets/marketing/share']"
      assert_select "meta[name='twitter:card'][content=summary_large_image]"
      assert_select "meta[name=robots]", false
      [ title, description ]
    end
    assert_equal seen.size, seen.map(&:first).uniq.size, "titles are unique"
    assert_equal seen.size, seen.map(&:last).uniq.size, "descriptions are unique"
  end

  test "structured data escapes what operators type in plan names" do
    Plan.listed.first.update!(name: "Evil</script><script>alert(1)</script>")
    get root_path
    assert_no_match %r{Evil</script>}, response.body
    assert_equal "Evil</script><script>alert(1)</script>", JSON.parse(css_select("script[type='application/ld+json']").first.text).last["offers"].first["name"]
  end

  test "the sitemap leaves out suspended businesses and closed request forms" do
    businesses(:one).update!(request_form_enabled: false, request_form_indexable: true)
    businesses(:two).update!(request_form_enabled: true, request_form_indexable: true, active: false)
    get "/sitemap.xml"
    assert_not_includes response.body, "/request/"
    assert_includes response.body, "http://example.com/legal/security</loc>", "the legal pages are listed (MKT-03)"
  end

  test "a legal document's current version is indexed, with its description (MKT-03)" do
    get legal_document_path("security")
    assert_select "meta[name=robots][content=noindex]", false
    assert_select "meta[name=description][content=?]", "Security & Trust: How we protect your data."
  end

  test "pages without their own description aren't indexed" do
    sign_in users(:one)
    get edit_user_registration_path
    assert_select "meta[name=robots][content=noindex]"
    assert_select "link[rel=canonical]", false
  end

  test "the canonical address ignores the query string" do
    get pricing_path(utm_source: "x")
    assert_select "link[rel=canonical][href=?]", "http://example.com/pricing"
  end

  test "the home page describes the organization and the product, with prices from the plans" do
    get root_path
    data = JSON.parse(css_select("script[type='application/ld+json']").first.text)
    assert_equal %w[Organization SoftwareApplication], data.map { _1["@type"] }
    assert_equal Plan.listed.map(&:name), data.last["offers"].map { _1["name"] }
  end

  test "robots keep the staff app, operator console, sign-in pages and client links out, and point to the sitemap" do
    get "/robots.txt"
    assert_response :success
    %w[/admin /c/ /users/ /invitations/].each { assert_includes response.body, "Disallow: #{_1}" }
    %w[/users/sign_in /users/sign_up].each { assert_includes response.body, "Allow: #{_1}" }
    assert_not_includes response.body, "/ops", "the console isn't advertised"
    assert_includes response.body, "Sitemap: http://example.com/sitemap.xml"
  end

  test "the sitemap lists the public pages and only the request pages businesses opted in to" do
    businesses(:one).update!(request_form_enabled: true, request_form_indexable: true)
    businesses(:two).update!(request_form_enabled: true, request_form_indexable: false)
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml", response.media_type
    urls = Nokogiri::XML(response.body).remove_namespaces!.xpath("//loc").map(&:text)
    PAGES.each { assert_includes urls, "http://example.com#{public_send(_1)}" }
    assert_includes urls, "http://example.com/request/#{businesses(:one).handle}"
    assert_not_includes urls, "http://example.com/request/#{businesses(:two).handle}"
  end

  test "request pages are noindex unless the business opts in" do
    business = businesses(:one)
    business.update!(request_form_enabled: true)
    get public_request_path(business.handle)
    assert_select "meta[name=robots][content=noindex]"
    business.update!(request_form_indexable: true)
    get public_request_path(business.handle)
    assert_select "meta[name=robots]", false
    assert_select "link[rel=canonical][href=?]", "http://example.com/request/#{business.handle}"
  end

  test "the staff app says noindex, and account pages other than sign-in and sign-up are kept out" do
    sign_in users(:one)
    get admin_root_path
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    sign_out :user
    get new_user_session_path
    assert_select "meta[name=robots]", false
    get new_user_password_path
    assert_select "meta[name=robots][content=noindex]"
  end
end
