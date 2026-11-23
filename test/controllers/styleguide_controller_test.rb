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

  test "PLT-15: the type scale's six steps are on the style guide, and the kit's titles take them from the theme" do
    get styleguide_path
    assert_equal [ "Page title", "Section title", "Card title", "Body", "Small", "Table header" ], css_select("section#type dt").map { _1.text.squish }
    theme = Rails.root.join("app/assets/tailwind/theme.css").read
    { "page-title" => "1.375rem", "page-title-phone" => "1.1875rem", "title" => "0.9375rem", "title-weight" => "650", "body" => "0.875rem", "small" => "0.8125rem" }.each do |step, value|
      assert_match(/--type-#{step}: #{Regexp.escape(value)};/, theme)
    end
    kit = Rails.root.join("app/assets/tailwind/components.css").read
    assert_match(/\.card-title, \.section-title, \.empty-title, \.modal-title, \.tour-title \{ font-size: var\(--type-title\); font-weight: var\(--type-title-weight\);/, kit)
    assert_match(/\.page-title \{ font-size: var\(--type-page-title-phone\);/, kit)
    assert_match(/\.table-head \{ font-size: var\(--type-small\); font-weight: 600; color: var\(--color-muted\);/, kit)
  end

  test "renders flash as a toast" do
    get styleguide_path(toast: 1)
    assert_select "#flash .toast", /Quote sent/
  end

  test "client layout applies the business brand without staff chrome" do
    get styleguide_client_path(brand: "#facc15")
    assert_response :success
    assert_select "head style[nonce]", /body\.client\{--color-brand: #facc15; --color-brand-button: #facc15; --color-brand-ink: #0f172a; --color-brand-hover: #fbd231; --color-brand-link: #876e0b;/
    assert_select ".client-head", /Oakline Lawn/
    assert_select ".side, .topbar", count: 0
  end

  test "rejects a malformed brand colour" do
    get styleguide_client_path(brand: "red;}")
    assert_select "head style[nonce]", /body\.client\{--color-brand: #047857;/
  end

  test "pages load no runtime CDN scripts or styles" do
    [ styleguide_path, root_path, pricing_path, new_user_session_path ].each do |path|
      get path
      assert_no_match %r{cdn\.tailwindcss|unpkg\.com|cdn\.jsdelivr}, response.body, path
      assert_select "link[rel='stylesheet'][href*='/assets/tailwind-']"
    end
  end
end
