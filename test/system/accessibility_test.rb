require "application_system_test_case"

# QA #274: an automated accessibility check (axe-core, WCAG 2.1 A and AA) on key app pages, and
# the behaviour the audit asked for that needs a browser: the dependent request-form setting,
# and toasts read out after a Turbo visit.
class AccessibilityTest < ApplicationSystemTestCase
  include AxeHelpers

  setup do
    @business = businesses(:one)
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  # PLT-14: the shared page list (test/support/staff_pages.rb), in three tests so they run in
  # parallel: the lists while empty, the detail pages in their main states, and everything else.
  # The operator console isn't swept here.
  test "the staff pages pass axe: empty lists" do
    assert_axe_clean StaffPages.empty # before any records exist
  end

  test "the staff pages pass axe: detail pages" do
    assert_axe_clean staff_pages.select(&:detail?)
  end

  test "the staff pages pass axe: lists, forms and settings" do
    @business.update!(weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5) # so Hours has its time inputs
    assert_axe_clean staff_pages.reject { _1.detail? || _1.ops? }
  end

  def staff_pages = StaffPages.build(@business, users(:one))

  def assert_axe_clean(pages)
    problems = pages.flat_map do |page|
      visit page.path
      axe_problems(page.to_s)
    end
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
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

  # JOB-12: the On my way sheet on My day (a dialog, loaded when it opens) closes with focus back
  # on its button; the sheet and the client's On the way card pass axe.
  test "On my way: the sheet on My day and the client's card pass axe, and the sheet gives focus back" do
    @business.update!(client_visit_emails: { "on_my_way" => "1" }, show_team_profiles: true)
    @business.business_users.find_by!(user: users(:one)).update!(photo: Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg"), title: "Owner")
    visit_record = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Job.create!(client:, title: "Spring cleanup").visits.new(scheduled_on: @business.today, timing: "anytime", assignee_ids: [ users(:one).id ])
         .tap { _1.schedule!(by: users(:one), notify_client: false) }
    end
    visit admin_my_day_path
    within("#my-visit-#{visit_record.uid}") { click_on "On my way" }
    assert_selector "dialog[open]", text: "Pick a time" # the sheet's frame has loaded
    problems = axe_problems("On my way sheet")
    find("dialog[open] button[aria-label=Close]").click
    assert_no_selector "dialog[open]"
    assert_equal "On my way", evaluate_script("document.activeElement.textContent").squish, "focus is back on the button"

    as_business(@business) { visit_record.update_columns(on_the_way_arrives_at: 30.minutes.from_now, on_the_way_by_id: users(:one).id) }
    visit client_link_path(as_business(@business) { visit_record.client_link! }.token)
    assert_selector "#on-the-way h2", text: "on the way"
    problems += axe_problems("client's On the way card")
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
      done = Job.create!(client:, title: "Done", line_items_attributes: [ { name: "Spraying", quantity: 1, unit_price: 40 } ]).tap { _1.complete!(by: users(:one)) }
      [ job, Invoice.from_job!(done, by: users(:one)).tap { _1.mark_sent!(by: users(:one), channel: "link") } ]
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
