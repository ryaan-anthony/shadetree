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
      axe_problems(path)
    end
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
  end

  # Axe on the page as it is now. An open dialog's fade-in (a <dialog>, or the tour's, ACC-08)
  # is let finish first: mid-fade, its text is partly transparent and the contrast check fails falsely.
  def axe_problems(label)
    execute_script(AXE.read) unless evaluate_script("typeof window.axe === 'object'")
    evaluate_async_script(<<~JS).map { "#{label}: #{_1}" }
      const done = arguments[0]
      const fading = [...document.querySelectorAll("dialog[open], [role=dialog]:not([hidden])")].flatMap((d) => d.getAnimations({ subtree: true }))
      Promise.all(fading.map((a) => a.finished))
        .then(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "best-practice"] } }))
        .then((r) => done(r.violations.map((v) => `${v.id} (${v.help}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`)))
    JS
  end

  # Each page loads in full (visit), so axe is injected afresh.
  test "key app pages pass axe" do
    @business.update!(weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5) # so Hours has its time inputs
    assert_accessible admin_root_path, admin_roles_path, admin_service_requests_path, admin_my_day_path, admin_hours_path,
                      edit_admin_business_path(tab: "documents"), edit_admin_business_path(tab: "request_form"),
                      edit_admin_business_path(tab: "branding"), admin_plan_path,
                      admin_notifications_path, admin_data_exports_path, admin_message_templates_path
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
                      admin_service_requests_path(status: "in_progress"),
                      admin_my_day_path, admin_my_request_path(request),
                      admin_schedule_path, admin_schedule_follow_up_path(request), admin_schedule_new_visit_path, # JOB-06, JOB-07
                      edit_admin_service_request_follow_up_path(request, from: "schedule", on: @business.today.iso8601, at: "10:00"),
                      admin_root_path # JOB-06: Home's own day lists it (owner, 2026-11-22)
    within("#todays-visits") do
      assert_text "Site visit for a request"
      click_on "Maria Lopez"
    end
    assert_current_path admin_my_request_path(request)
  end

  # JOB-08: Busy blocks for someone who schedules but can't see requests: the week, a day by
  # person, by status, and the phone agenda with its folded earlier days.
  test "the calendar with Busy blocks passes axe, wide and on a phone" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    monday = @business.today.beginning_of_week
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Fence").then { RequestFollowUp.assign!(_1, { user: users(:one), scheduled_on: monday, timing: "exact", start_time: "10:00" }, by: users(:one)) }
      ServiceRequest.create!(client:, source: "phone", description: "Hedges").then { RequestFollowUp.assign!(_1, { user: users(:one), kind: "call", scheduled_on: monday + 6 }, by: users(:one)) }
      dispatcher = Role.create!(name: "Dispatcher", permissions: %w[schedule])
      dee = User.create!(email: "dee@example.com", password: "password123", first_name: "Dee", confirmed_at: Time.current)
      BusinessUser.create!(user: dee, business: @business, role: "custom", role_id: dispatcher.id)
    end
    Capybara.reset_sessions!
    visit new_user_session_path
    sign_in_with_form("dee@example.com")
    assert_text "Schedule"
    paths = [ admin_schedule_path(date: monday.iso8601), admin_schedule_path(date: monday.iso8601, view: "day"), admin_schedule_path(date: monday.iso8601, color: "status") ]
    assert_accessible(*paths)
    assert_selector ".cal-busy", text: "Busy"
    page.driver.browser.manage.window.resize_to(390, 844)
    assert_accessible(*paths)
    assert_selector "#schedule-agenda", text: "Busy"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  # JOB-06: a done follow-up, with a site photo they can remove, on My day and its own page, and
  # its Pass back dialog open.
  test "a done follow-up, its site photo and the Pass back dialog pass axe" do
    tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: tech, business: @business, role: "technician")
    request = Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Fence repair").tap do
        RequestFollowUp.assign!(_1, { user: users(:one), scheduled_on: @business.today }, by: tech) # so it can go back to Marcus
        assert_nil _1.add_site_photo_from(Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png"), by: users(:one))
        _1.reload.follow_up.done!(by: users(:one))
      end
    end
    assert_accessible admin_my_day_path
    assert_selector "#my-request-#{request.uid} .badge", text: "Done"
    assert_accessible admin_my_request_path(request)
    assert_button "Remove site photo 1"
    click_on "Pass back to Marcus Reyes"
    assert_selector "dialog[open]", text: "Pass this back to Marcus Reyes?"
    problems = axe_problems("Pass back dialog")
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
  end

  # ACC-08: the guided tour, open at the checklist and at a menu stop, wide and on a phone
  # (where the menu drawer is open beside the sheet).
  test "the guided tour passes axe while it's open" do
    @business.update!(onboarded_at: nil)
    problems = []
    [ [ 1400, 1400, "wide" ], [ 390, 844, "phone" ] ].each do |width, height, label|
      page.driver.browser.manage.window.resize_to(width, height)
      visit admin_root_path
      click_on "Help"
      click_on "Take the tour again"
      assert_selector "#tour[role=dialog]", text: "Start here"
      problems += axe_problems("#{label}, checklist stop")
      click_on "Next"
      assert_selector "[data-tour=requests].tour-target"
      assert_selector "#app-sidebar[data-open=true]" if label == "phone"
      problems += axe_problems("#{label}, menu stop")
      click_on "End tour"
    end
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  # #289: the forms with a summary beside them (Schedule a visit, Record a payment).
  test "the split forms pass axe" do
    job, invoice = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "2155551212" } ])
      job = Job.create!(client:, title: "Ants", line_items_attributes: [ { name: "Spraying", quantity: 1, unit_price: 40 } ])
      [ job, Invoice.from_job!(job, by: users(:one)).tap { _1.mark_sent!(by: users(:one), channel: "link") } ]
    end
    assert_accessible new_admin_job_visit_path(job), new_admin_invoice_payment_path(invoice), new_admin_service_request_path
  end

  # QTE-08: the switch, the cap and a technician's reason, on a 360 px phone, with no sideways scroll.
  test "sending without review: the switch, the cap and the reasons pass axe at 360 px" do
    tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: tech, business: @business, role: "technician")
    gutters, quote = as_business(@business) do
      gutters = CatalogItem.create!(name: "Gutter clean", unit: "visit", unit_price: "150", send_without_review: true)
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      request = ServiceRequest.create!(client:, source: "phone", description: "Gutters")
      quote = request.create_quote!(by: tech)
      quote.sync_line_items([ { "key" => "a", "catalog_item" => gutters.uid, "name" => "Gutter clean", "unit" => "visit", "unit_price" => "140", "quantity" => "1" } ])
      quote.save!
      [ gutters, quote ]
    end
    @business.update!(without_review_cap: "500")
    page.current_window.resize_to(360, 740)
    problems = []
    [ admin_catalog_items_path, edit_admin_catalog_item_path(gutters) ].each do |path|
      visit path
      problems += axe_problems(path)
      assert_operator evaluate_script("document.documentElement.scrollWidth"), :<=, 360, path
    end
    assert_field "Technicians can send without review", checked: true, visible: :all
    Capybara.reset_sessions!
    visit new_user_session_path
    sign_in_with_form(tech.email, "password123")
    visit edit_admin_quote_path(quote)
    assert_selector "#review-reason", text: "Needs the office's review: Gutter clean: price changed"
    problems += axe_problems("the builder's reason")
    assert_operator evaluate_script("document.documentElement.scrollWidth"), :<=, 360
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
  ensure
    page.current_window.resize_to(1400, 1400)
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
    click_on "Taxes" # a Turbo visit; the page with the toast is cached
    assert_selector "h2", text: "Tax rates"
    execute_script(<<~JS)
      window.__announced = []
      new MutationObserver(() => { const t = document.getElementById("announcer").textContent; if (t) window.__announced.push(t) })
        .observe(document.getElementById("announcer"), { childList: true, characterData: true, subtree: true })
    JS
    page.go_back
    assert_selector "nav[aria-label=Settings] a[aria-current=page]", text: "Quotes, jobs & invoices"
    assert_no_selector "#flash .toast"
    sleep 0.5 # longer than an announcement takes to land
    assert_empty evaluate_script("window.__announced"), "nothing is read out again"
  end

  test "a toast after a Turbo visit is copied into the page's live region" do
    visit edit_admin_business_path(tab: "documents")
    click_on "Save changes"
    assert_selector "#flash .toast:not([role])", text: "Settings saved." # read through #announcer, not twice
    assert_selector "#announcer[role=status]", text: "Settings saved.", visible: :all
    assert_selector "nav[aria-label=Settings] a[aria-current=page]", text: "Quotes, jobs & invoices"
  end
end
