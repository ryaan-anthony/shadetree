require "test_helper"

# QA/accessibility audit #274, marketing and public pages: the Shadetree wordmark, landmarks,
# short links and branded error pages.
class MarketingAccessibilityTest < ActionDispatch::IntegrationTest
  PAGES = %w[/ /features /pricing /about /contact /legal /terms /privacy /legal/security /users/sign_in /users/sign_up].freeze

  test "every marketing page has a skip link, header with the main nav, main and footer, and the wordmark" do
    PAGES.each do |path|
      get path
      assert_response :success, path
      assert_select "body > a[href='#main']:first-of-type", "Skip to content"
      assert_select "body > header nav[aria-label=Main] a.logo[aria-label='Shadetree home'] .wordmark:not(.wordmark-dark)", 1, path
      assert_select "main#main", 1
      assert_select "body > footer .logo .wordmark.wordmark-dark .wordmark-shade", "Shade"
      assert_select "title", /· Shadetree\z/
    end
  end

  test "the name is spelled Shadetree everywhere" do
    PAGES.each do |path|
      get path
      assert_no_match(/Shade[ -]?Tree|SHADETREE|shade tree/, response.body, path)
    end
  end

  test "short links go where people expect" do
    get "/security"
    assert_redirected_to "/legal/security"
    get "/help"
    assert_redirected_to "/admin/help"
    follow_redirect!
    assert_redirected_to new_user_session_path, "signed out, help asks for sign-in first"
    get "/terms"
    assert_response :success
    get "/privacy"
    assert_response :success
  end

  test "the static error pages are branded, with a skip link, landmarks, one H1 and a way home" do
    { "400" => "We couldn't read that request", "404" => "We can't find that page", "406-unsupported-browser" => "Your browser isn't supported",
      "422" => "That didn't go through", "429" => "That was a lot of requests in a short time",
      "500" => "Something went wrong on our side" }.each do |code, heading|
      page = Nokogiri::HTML5(Rails.public_path.join("#{code}.html").read)
      assert_equal "a", page.at_css("body > *:first-child").name, code
      assert_equal "#main", page.at_css("body > a.skip")["href"]
      assert page.at_css("body > header nav[aria-label=Main] a[href='/'][aria-label='Shadetree home'] .shade"), code
      assert_equal [ heading ], page.css("main#main h1").map(&:text), code
      assert page.at_css("main a[href='/']"), code
      assert page.at_css("body > footer a[href='/legal/security']"), code
      assert_match(/ · Shadetree\z/, page.at_css("title").text)
      assert_no_match(/rails|application owner|logs/i, page.text, code)
    end
  end

  test "staff emails carry the wordmark" do
    mail = AccountMailer.with(email: "solo@example.com", first_name: "Sam").deleted
    assert_includes mail.html_part.body.to_s, %(<span style="color:#059669;">Shade</span>tree)
  end
end
