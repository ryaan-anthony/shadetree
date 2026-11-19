require "test_helper"

# MKT-01: the Features page (real screenshots, nothing promised that isn't built) and About.
class MarketingFeaturesAndAboutTest < ActionDispatch::IntegrationTest
  test "features covers quoting, approval, scheduling, the crew and invoicing, each with a real screenshot" do
    get features_path
    assert_response :success
    assert_select "title", /Features/
    assert_select "h1", 1
    %w[quoting approval scheduling crew invoicing].each do |section|
      assert_select "section##{section} h2"
      assert_select "section##{section} img[src*='/assets/marketing/'][alt]:not([alt=''])"
      assert_select "nav[aria-label='On this page'] a[href=?]", "##{section}"
    end
    assert_select "a[href=?]", new_user_registration_path, text: "Start free"
    assert_select "header nav a[href=?][aria-current=page]", features_path
  end

  test "the screenshots exist and stay small" do
    Dir[Rails.root.join("app/assets/images/marketing/*.webp")].tap { assert_equal 10, _1.size, "each screenshot and its small version" }.each do |file|
      assert_operator File.size(file), :<, 120.kilobytes, "#{File.basename(file)} is too big for a marketing page"
    end
  end

  test "no claims about features that aren't built yet" do
    [ features_path, about_path, root_path ].each do |path|
      get path
      assert_no_match(/pay online|pay by card|card or wallet|apple pay|automatic(ally)? follow|text message reminders|testimonial|trusted by/i,
                      response.body, "#{path} promises something not built")
    end
  end

  test "about tells why Shadetree exists and what it promises, and links to contact" do
    get about_path
    assert_response :success
    assert_select "h1", /crews who keep neighborhoods running/
    assert_select "#promises-heading + dl dt", 6
    assert_select "a[href=?]", contact_path, text: "Get in touch"
    assert_select "img", false, "no stock photos of people who don't work here"
  end
end
