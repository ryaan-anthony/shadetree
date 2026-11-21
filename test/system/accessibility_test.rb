require "application_system_test_case"

# QA #274: an automated accessibility check (axe-core, WCAG 2.1 A and AA) on key app pages, and
# the behaviour the audit asked for that needs a browser: the dependent request-form setting,
# and toasts read out after a Turbo visit.
class AccessibilityTest < ApplicationSystemTestCase
  AXE = Pathname(Gem.loaded_specs.fetch("axe-core-api").full_gem_path).join("node_modules/axe-core/axe.min.js")

  setup do
    @business = businesses(:one)
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  def assert_accessible(path)
    visit path
    execute_script(AXE.read) unless evaluate_script("typeof window.axe === 'object'")
    violations = evaluate_async_script(<<~JS)
      const done = arguments[0]
      axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"] } })
        .then((r) => done(r.violations.map((v) => `${v.id} (${v.help}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`)))
    JS
    assert_empty violations, "axe found problems on #{path}"
  end

  # Each page loads in full (visit), so axe is injected afresh; a failure lists the rule and
  # the first elements that break it.
  test "key app pages pass axe" do
    [ admin_root_path, admin_roles_path, admin_service_requests_path, admin_my_day_path, admin_hours_path, edit_admin_business_path(tab: "documents"),
      edit_admin_business_path(tab: "request_form"), admin_plan_path, admin_notifications_path, admin_data_exports_path ].each do |path|
      assert_accessible path
    end
  end

  test "the search-engine setting is off while requests are off" do
    @business.update!(request_form_enabled: true)
    visit edit_admin_business_path(tab: "request_form")
    assert_field "Let search engines find your request page", disabled: false
    uncheck "Take requests online"
    assert_field "Let search engines find your request page", disabled: true
    check "Take requests online"
    assert_field "Let search engines find your request page", disabled: false
  end

  test "a toast after a Turbo visit is copied into the page's live region" do
    visit edit_admin_business_path(tab: "documents")
    click_on "Save changes"
    assert_selector "#flash .toast[role=status]", text: "Settings saved."
    assert_selector "#announcer[role=status]", text: "Settings saved.", visible: :all
    assert_selector "nav[aria-label=Settings] a[aria-current=page]", text: "Documents"
  end
end
