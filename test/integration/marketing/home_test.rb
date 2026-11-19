require "test_helper"

# MKT-01: the home page says what Shadetree does, shows the plans from plan data (BIL-01), and
# leads to one action: Start free.
class MarketingHomeTest < ActionDispatch::IntegrationTest
  test "the core loop, who it's for, how it works and one call to action" do
    get root_path
    assert_response :success
    assert_select "title", /quotes, scheduling and payments/i
    assert_select "meta[name=description]"
    assert_select "h1", /Quote it.\s*Book it.\s*Get paid./m
    assert_select "a[href=?]", new_user_registration_path, text: "Start free", minimum: 2
    assert_select "#how-it-works ol > li", 4
    Industry.all.reject { _1.key == "other" }.each { |industry| assert_includes response.body, ERB::Util.h(industry.name) }
    assert_select "#features h2", 2
  end

  test "the pricing teaser comes from the plans, and hidden plans aren't shown" do
    get root_path
    Plan.listed.each do |plan|
      assert_select "li", /#{Regexp.escape(plan.name)}.*#{Regexp.escape(plan.monthly_price.format.delete_suffix(".00"))}/m
    end
    assert_select "a[href=?]", pricing_path, text: "Compare plans"
    hidden = Plan.listed.first
    hidden.update!(public: false)
    get root_path
    assert_select "#pricing-teaser ~ ul li", Plan.listed.count
  end

  test "no fabricated metrics, logos or testimonials, and no promises the app doesn't keep" do
    get root_path
    assert_no_match(/testimonial|trusted by|\d+% |customers love|14-day|trial|per seat|contact sales/i, response.body)
  end

  test "the bottom box carries the email into sign-up" do
    get root_path
    assert_select "form[action=?][method=get] input[name=email][type=email]", new_user_registration_path
    get new_user_registration_path(email: " ana@example.com ")
    assert_select "input[name='user[email]'][value=?]", "ana@example.com"
  end

  test "navigation and footer are the same on every public page, with the legal links" do
    [ root_path, pricing_path, about_path, contact_path, new_user_session_path ].each do |path|
      get path
      assert_select "header nav[aria-label=Main] a[href=?]", pricing_path
      assert_select "header a[href=?]", new_user_registration_path, text: "Start free"
      assert_select "footer #legal-links a[href=?]", terms_path
      assert_select "footer #legal-links a[href=?]", privacy_path
      assert_select "select", false, "no language picker that does nothing"
    end
  end
end
