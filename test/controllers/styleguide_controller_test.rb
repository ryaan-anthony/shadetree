require "test_helper"

class StyleguideControllerTest < ActionDispatch::IntegrationTest
  test "shows every component section" do
    get styleguide_path
    assert_response :success
    %w[colors type buttons forms badges cards tables dialogs feedback navigation icons layouts].each do |id|
      assert_select "section##{id}"
    end
    assert_select "dialog#confirm-dialog"
    assert_select "dialog#sample-modal"
  end

  test "renders flash as a toast" do
    get styleguide_path(toast: 1)
    assert_select "#flash .toast", /Quote sent/
  end

  test "client layout applies the business brand without staff chrome" do
    get styleguide_client_path(brand: "#facc15")
    assert_response :success
    assert_select "body.client[style*='--color-brand: #facc15'][style*='--color-brand-ink: #0f172a']"
    assert_select ".client-head", /Oakline Lawn/
    assert_select ".side, .topbar", count: 0
  end

  test "rejects a malformed brand colour" do
    get styleguide_client_path(brand: "red;}")
    assert_select "body.client[style*='--color-brand: #047857']"
  end

  test "pages load no runtime CDN scripts or styles" do
    [ styleguide_path, root_path, pricing_path, new_user_session_path ].each do |path|
      get path
      assert_no_match %r{cdn\.tailwindcss|unpkg\.com|cdn\.jsdelivr}, response.body, path
      assert_select "link[rel='stylesheet'][href*='/assets/tailwind-']"
    end
  end
end
