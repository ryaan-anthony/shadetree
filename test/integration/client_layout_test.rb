require "test_helper"

# QA #274: client pages (business-branded, no Shadetree navigation) have a skip link, a header
# with the business's name or logo, main and a footer; phones are formatted and dialable.
class ClientLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(handle: "oakline", request_form_enabled: false, phone: "2155551212", email: "office@oakline.example.com")
  end

  test "the request page with requests off: landmarks, and how to get in touch" do
    get public_request_path("oakline")
    assert_response :success
    assert_select "body > a[href='#main']:first-child[class*='focus:z-[200]']", "Skip to content" # first, above the banner
    assert_select "body > header.client-head", /#{Regexp.escape(@business.name)}/
    assert_select "main#main h1", "Get in touch with #{@business.name}"
    assert_select "body > footer a", /Powered by\s*Shadetree/
    assert_select "nav[aria-label=Main]", false, "no Shadetree marketing navigation on client pages"
    assert_select "header a[href='tel:+12155551212']", "(215) 555-1212"
    assert_select "main a[href='tel:+12155551212']", /Call \(215\) 555-1212/
    assert_select "main a[href='mailto:office@oakline.example.com']"
  end

  test "without a phone or email it still says what's going on" do
    @business.update!(phone: nil, email: nil)
    get public_request_path("oakline")
    assert_select "main p", /Online requests are off right now. Please check back soon./
  end

  test "a logo gets its size up front, and its alt text is the name (not said twice)" do
    @business.update!(logo: { io: file_fixture("logo.png").open, filename: "logo.png" })
    @business.logo.blob.analyze
    get public_request_path("oakline")
    image = css_select("header.client-head img.client-logo-image").sole
    assert_equal @business.name, image["alt"]
    assert image["width"].to_i.positive? && image["height"].to_i.positive?, "width and height are set"
    assert_select "header.client-head p", { text: @business.name, count: 0 }
  end
end
