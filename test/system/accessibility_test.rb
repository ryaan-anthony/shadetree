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

  # Runs axe (WCAG 2.1 A/AA and best practices: heading order, landmarks, content in a region)
  # on each page, and fails once, listing every page's problems.
  def assert_accessible(*paths)
    problems = paths.flat_map do |path|
      visit path
      execute_script(AXE.read) unless evaluate_script("typeof window.axe === 'object'")
      evaluate_async_script(<<~JS).map { "#{path}: #{_1}" }
        const done = arguments[0]
        axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "best-practice"] } })
          .then((r) => done(r.violations.map((v) => `${v.id} (${v.help}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`)))
      JS
    end
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
  end

  # Each page loads in full (visit), so axe is injected afresh.
  test "key app pages pass axe" do
    @business.update!(weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5) # so Hours has its time inputs
    assert_accessible admin_root_path, admin_roles_path, admin_service_requests_path, admin_my_day_path, admin_hours_path,
                      edit_admin_business_path(tab: "documents"), edit_admin_business_path(tab: "request_form"),
                      edit_admin_business_path(tab: "branding"), admin_plan_path,
                      admin_notifications_path, admin_data_exports_path
  end

  # CLI-07: logging a request (with its follow-up fields), a request with a follow-up, and the assign form.
  test "request follow-up pages pass axe" do
    request = Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Fence repair").tap do
        RequestFollowUp.assign!(_1, { user: users(:one), scheduled_on: @business.today }, by: users(:one))
      end
    end
    assert_accessible new_admin_service_request_path, admin_service_request_path(request), edit_admin_service_request_follow_up_path(request),
                      admin_service_requests_path(status: "in_progress")
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

  test "Back to a page that had a toast says nothing again" do
    visit edit_admin_business_path(tab: "documents")
    click_on "Save changes"
    assert_selector "#announcer", text: "Settings saved.", visible: :all
    click_on "Hours" # a Turbo visit; the page with the toast is cached
    assert_selector "h2", text: "Weekly hours"
    execute_script(<<~JS)
      window.__announced = []
      new MutationObserver(() => { const t = document.getElementById("announcer").textContent; if (t) window.__announced.push(t) })
        .observe(document.getElementById("announcer"), { childList: true, characterData: true, subtree: true })
    JS
    page.go_back
    assert_selector "nav[aria-label=Settings] a[aria-current=page]", text: "Documents"
    assert_no_selector "#flash .toast"
    sleep 0.5 # longer than an announcement takes to land
    assert_empty evaluate_script("window.__announced"), "nothing is read out again"
  end

  test "a toast after a Turbo visit is copied into the page's live region" do
    visit edit_admin_business_path(tab: "documents")
    click_on "Save changes"
    assert_selector "#flash .toast:not([role])", text: "Settings saved." # read through #announcer, not twice
    assert_selector "#announcer[role=status]", text: "Settings saved.", visible: :all
    assert_selector "nav[aria-label=Settings] a[aria-current=page]", text: "Documents"
  end
end
