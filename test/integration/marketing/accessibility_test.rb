require "test_helper"

# QA/accessibility audit #274, marketing and public pages: the Shadetree wordmark, landmarks,
# real lists, short links, branded error pages, the contact form and pricing.
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

  test "the hero quote is text, with the subtotal, tax and total that add up" do
    get root_path
    assert_select "figure figcaption.sr-only"
    assert_select "figure[aria-hidden]", false
    assert_select "figure ul li", 4
    assert_select "figure dl" do
      assert_select "dt", "Subtotal"
      assert_select "dd", "$1,243.00"
      assert_select "dt", "Sales tax (7.25%)"
      assert_select "dd", "$90.12"
      assert_select "dd", "$1,333.12"
    end
    assert_equal BigDecimal("1333.12"), (BigDecimal("1243.00") * BigDecimal("1.0725")).round(2)
  end

  test "home page lists are lists" do
    get root_path
    assert_select "ul[aria-labelledby=made-for] li", Industry.all.size # every industry but "other", and "other crews"
    assert_select "dl > div > dt", "Your data is yours"
  end

  test "legal pages use real lists, and Privacy's terms are a description list" do
    get terms_path
    assert_select "article.legal-text ul > li", minimum: 7
    get privacy_path
    assert_select "article.legal-text dl > div > dt", "Your account:"
    assert_select "article.legal-text dl > div > dd", /your name, email, a hashed password/
    assert_select "article.legal-text li strong", false, "term lists are <dl>, not bold list items"
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

  test "contact: one title, spaced optional labels, one Something else, and marked required fields" do
    get contact_path
    assert_select "title", "Contact · Shadetree"
    assert_select "label[for=contact_message_business_name]", "Business name (optional)"
    assert_select "#contact_message_industry option[value=other]", 1
    assert_select "#contact_message_industry option", text: "Other", count: 0
    assert_select "p", "Fields marked * are required."
    %w[name email body].each do |field|
      assert_select "label[for=contact_message_#{field}] .label-required[aria-hidden=true]", "*"
      assert_select "#contact_message_#{field}[required]"
    end
    assert_select "label[for=contact_message_business_name] .label-required", false
  end

  test "pricing: a descriptive contact link, a status region for the switch, and FAQ cues" do
    get pricing_path
    assert_select "a[href=?]", contact_path, text: "Contact us about choosing a plan"
    assert_select "a", text: "Ask us", count: 0
    assert_select "[data-controller=billing-switch][data-billing-switch-yearly-value*='billed yearly']"
    assert_select "p.sr-only[role=status][data-billing-switch-target=status]"
    assert_select "input[name=billing][data-action='billing-switch#announce']", 2
    assert_select "details summary.group-open\\:text-canopy", minimum: 4
  end

  test "the Free plan's quota matches the features screenshot (3 of 5 quotes sent)" do
    free = YAML.safe_load_file(Rails.root.join("db/seeds/plans.yml")).fetch("free")
    assert_equal 5, free.dig("limits", "quotes_sent"), "retake app/assets/images/marketing/builder*.webp (MKT-01) when this changes"
  end

  test "staff emails carry the wordmark" do
    mail = AccountMailer.with(email: "solo@example.com", first_name: "Sam").deleted
    assert_includes mail.html_part.body.to_s, %(<span style="color:#059669;">Shade</span>tree)
  end
end
