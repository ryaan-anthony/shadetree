require "test_helper"

# PLT-13: the content security policy and the headers that go with it, and that no page needs
# what the policy forbids (style attributes, inline handlers, scripts or styles without the nonce).
class SecurityHeadersTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers

  def csp = response.headers["Content-Security-Policy"]

  def nonce = csp[/'nonce-([^']+)'/, 1]

  # Everything the policy would block on this page.
  def assert_csp_clean(page)
    html = Nokogiri::HTML(response.body)
    assert_empty html.xpath("//*[@style]").map(&:name), "#{page}: style attributes"
    assert_empty html.xpath("//@*[starts-with(name(), 'on')]").map(&:name), "#{page}: inline event handlers"
    assert_empty html.css("a[href^='javascript:']"), "#{page}: javascript: links"
    html.css("script:not([src]), style").each do |element|
      assert_equal nonce, element["nonce"], "#{page}: <#{element.name}> without the page's nonce"
    end
  end

  test "pages send a strict policy and secure headers" do
    get root_path
    assert_response :success
    policy = csp.split(/;\s*/).to_h { _1.split(" ", 2) }
    assert_equal "'self' 'nonce-#{nonce}'", policy["script-src"]
    assert_equal "'self' 'nonce-#{nonce}'", policy["style-src"]
    assert_equal "'none'", policy["frame-ancestors"]
    assert_equal "'none'", policy["object-src"]
    assert_equal "'self'", policy["form-action"]
    assert_equal "'self'", policy["base-uri"]
    assert_equal "/csp-reports", policy["report-uri"]
    assert_no_match(/unsafe-inline|unsafe-eval|\*/, csp)
    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    assert_match "camera=()", response.headers["Permissions-Policy"]
    assert_match "geolocation=()", response.headers["Permissions-Policy"]
  end

  test "the session cookie is HTTP-only and same-site, and sign-in starts a new session" do
    get new_user_session_path
    before = session.id.to_s
    post user_session_path, params: { user: { email: users(:one).email, password: "password123" } }
    assert_response :redirect
    cookie = Array(response.headers["Set-Cookie"]).flat_map { _1.split("\n") }.find { _1.start_with?("_shadetree_session=") }
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
    assert_not_equal before, session.id.to_s, "a session id fixed before sign-in doesn't carry over"
  end

  test "public, signed-in and client pages need nothing the policy blocks" do
    business = businesses(:one)
    business.update!(brand_color: "#9a3412")
    { "home" => root_path, "pricing" => "/pricing", "sign in" => new_user_session_path, "sign up" => new_user_registration_path,
      "request form" => public_request_path(business.handle) }.each do |page, path|
      get path
      assert_response :success, page
      assert_csp_clean(page)
    end

    create_test_document_table
    link = as_business(business) { ClientLink.issue!(create_test_document(business), actions: %w[approve]) }
    get client_link_path(link.token)
    assert_csp_clean("client page")
    assert_select "head style[nonce=?]", nonce, /--color-brand: #9a3412/

    sign_in users(:one)
    post switch_admin_business_path, params: { business: business.uid }
    monday = Date.new(2026, 11, 23)
    as_business(business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      job = Job.create!(client:, title: "Spring cleanup")
      job.visits.new(scheduled_on: monday, timing: "exact", start_time: "09:00", duration_minutes: 90).schedule!(by: users(:one))
    end
    { "dashboard" => admin_root_path, "schedule" => admin_schedule_path(date: monday.iso8601),
      "branding" => edit_admin_business_path(tab: "branding"), "styleguide" => "/styleguide" }.each do |page, path|
      get path
      assert_response :success, page
      assert_csp_clean(page)
    end
    get admin_schedule_path(date: monday.iso8601)
    visit_class = css_select(".cal-visit").first["class"][/is-\h+/]
    assert_match(/\.#{visit_class}\{top: \d+px; height: \d+px; left: calc/, css_select("style[nonce]").map(&:text).join)
  end

  test "violation reports are logged, and anything else is ignored quietly" do
    io = StringIO.new
    logger, Rails.logger = Rails.logger, ActiveSupport::Logger.new(io)
    begin
      post csp_reports_path, params: { "csp-report" => { "document-uri" => "https://getshadetree.com/x", "violated-directive" => "script-src", "blocked-uri" => "inline", "secret" => "nope" } }.to_json,
                             headers: { "CONTENT_TYPE" => "application/csp-report" }
      assert_response :no_content
      post csp_reports_path, params: [ { "type" => "csp-violation", "body" => { "effectiveDirective" => "style-src-attr" } } ].to_json,
                             headers: { "CONTENT_TYPE" => "application/reports+json" }
      post csp_reports_path, params: "not json", headers: { "CONTENT_TYPE" => "text/plain" }
      assert_response :no_content
    ensure
      Rails.logger = logger
    end
    logged = io.string.lines.grep(/\[csp\]/)
    assert_equal 2, logged.size
    assert_match "script-src", logged.first
    assert_no_match "secret", logged.first
    assert_match "style-src-attr", logged.last
  end

  test "security.txt names a contact and hasn't expired" do
    text = Rails.root.join("public/.well-known/security.txt").read
    assert_match %r{^Contact: mailto:security@getshadetree\.com$}, text
    expires = Time.iso8601(text[/^Expires: (.+)$/, 1])
    assert expires > 60.days.from_now, "security.txt expires #{expires.to_date}: renew it (RFC 9116 wants under a year ahead)"
  end
end
