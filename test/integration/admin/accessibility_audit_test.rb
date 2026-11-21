require "test_helper"

# QA/accessibility audit #274, app pages: names, headings, landmarks, current tabs, status
# messages and copy. (Behaviour in a browser, and axe, are in test/system/accessibility_test.rb.)
class Admin::AccessibilityAuditTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "the app layout has header, nav, main and footer landmarks; the sidebar isn't complementary" do
    get admin_root_path
    assert_select "body header.topbar"
    assert_select "nav[aria-label=Primary]"
    assert_select "main#main"
    assert_select "#app-sidebar > footer.side-foot a[href=?]", terms_path
    assert_select "aside#app-sidebar", 0
  end

  test "Documents settings: each field has its own label and id" do
    get edit_admin_business_path(tab: "documents")
    { "business_quote_number_prefix" => "Quote number prefix", "business_invoice_number_prefix" => "Invoice number prefix",
      "business_quote_terms" => "Quote terms", "business_invoice_terms" => "Invoice terms" }.each do |id, label|
      assert_select "input##{id}, textarea##{id}", 1
      assert_select "label[for=#{id}]", /\A#{label}/
    end
    assert_select "label", { text: /\ANumber prefix/, count: 0 }
    assert_select ".banner-info[role=status]", /starting points/
  end

  test "Hours: day boxes and times are named by their day, and the zone sentence reads right" do
    get admin_hours_path
    assert_select "label.check", /Open on\s*Monday/
    assert_select "label[for=hours_1_opens]", "Monday opening time"
    assert_select "label[for=hours_1_closes]", "Monday closing time"
    assert_select ".card-subtitle", /Times are in Eastern Time \(US & Canada\)\./
    assert_no_match(/\) time\./, response.body)
    assert_select "h3.empty-title", "No closures coming up" # under the Closures card's H2
  end

  test "empty states are H2 under the page's H1" do
    get admin_service_requests_path
    assert_select "h2.empty-title", "You're all caught up"
    assert_select "h3.empty-title", 0
  end

  test "repeated links say what they're for" do
    get admin_data_exports_path
    assert_select "a[aria-label='Download CSV: Clients']", "Download CSV"
    assert_select "summary[aria-label='Columns: Clients']", "Columns"
    assert_no_match(/\([A-Z]{2,4}-\d+\)/, response.body.gsub(/<!--.*?-->/m, ""), "no spec codes in the copy")

    get admin_message_templates_path
    assert_select "a[aria-label=?]", "View: #{EmailCatalog.find("quote_sent").name}", "View" # Free: templates are read-only
  end

  test "catalog Add here links name their category" do
    as_business(@business) do
      category = CatalogCategory.create!(name: "Lawn care")
      CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45", category:)
      CatalogItem.create!(name: "Mulch", unit: "each", unit_price: "5")
    end
    get admin_catalog_items_path
    assert_select "a[aria-label='Add here: Lawn care']", "Add here"
    assert_select "a[aria-label='Add here: Uncategorized']", "Add here"
  end

  test "tax rates offer one Add action at a time" do
    get admin_tax_rates_path
    assert_select "a[href=?]", new_admin_tax_rate_path, 1
    assert_select "h3.empty-title", "No tax rates"
    as_business(@business) { TaxRate.create!(name: "State", percent: "6.25") }
    get admin_tax_rates_path
    assert_select "a[href=?]", new_admin_tax_rate_path, { count: 1, text: /Add a tax rate/ }
  end

  test "settings tabs mark the current one" do
    get admin_hours_path
    assert_select "nav[aria-label=Settings] a[aria-current=page]", { count: 1, text: "Hours" }
    get admin_service_requests_path(status: "new")
    assert_select "nav[aria-label='Requests by status'] a[aria-current=page]", 1
  end

  test "the plan page keeps each feature with whether it's included, and says what a zero limit means" do
    @business.update!(plan_overrides: { "limits" => { "active_automations" => 0 } }) # as Free is in production
    get admin_plan_path
    assert_select "#plan-features #feature-custom_roles dt", "Custom roles"
    assert_select "#plan-features #feature-custom_roles dd", "Not included"
    assert_select "#plan-features svg[aria-hidden=true]", Plan::FEATURES.size
    assert_select "#limit-active_automations dd", "Not included on Free"
    assert_select "#compare-plans svg[role=img]", 0, "table icons are decoration; the cell's text says it"
    assert_select "#compare-plans td .sr-only", /Included|Not included/
    assert_no_match(/coming soon/i, response.body)
  end

  test "notifications show Unread and a labelled Mark as read" do
    as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      NotificationType.deliver("new_request", business: @business, subject: client, title: "New request from Maria", path: "/admin")
    end
    get admin_notifications_path
    assert_select "#notifications li .badge", "Unread"
    assert_select "#notifications button[aria-label='Mark as read: New request from Maria']", /Mark as read/
  end

  test "search engines can't be chosen while requests are off, and the choice is ignored then" do
    @business.update!(request_form_enabled: false, request_form_indexable: false)
    get edit_admin_business_path(tab: "request_form")
    assert_select "input#business_request_form_indexable[disabled]"
    assert_select "[data-controller=dependent] input#business_request_form_enabled[data-dependent-target=source]"

    patch admin_business_path(tab: "request_form"), params: { business: { request_form_enabled: "0", request_form_indexable: "1" } }
    assert_not @business.reload.request_form_indexable?, "ignored while requests are off"
    patch admin_business_path(tab: "request_form"), params: { business: { request_form_enabled: "1", request_form_indexable: "1" } }
    assert @business.reload.request_form_indexable?
    patch admin_business_path(tab: "request_form"), params: { business: { request_form_enabled: "0" } }
    assert @business.reload.request_form_indexable?, "turning requests off keeps the choice for later"
  end

  test "toasts: notices are status, alerts are alert, and there's a live region kept across visits" do
    patch admin_business_path(tab: "documents"), params: { business: { quote_expiry_days: "30" } }
    follow_redirect!
    assert_select "#announcer[role=status][aria-live=polite][data-turbo-permanent]"
    assert_select "#flash .toast[role=status][data-controller~=announce]", /Settings saved/
    post switch_admin_business_path, params: { business: "nope" }
    follow_redirect!
    assert_select "#flash .toast[role=alert]", /isn't available/
    assert_select "#flash .toast[role=alert][data-controller~=announce]", 0, "alerts announce themselves"
  end

  test "the confirm-your-email banner shows only to unconfirmed people" do
    get admin_root_path
    assert_select "#confirm-email-banner", 0
    @owner.update_columns(confirmed_at: nil)
    get admin_root_path
    assert_select "#confirm-email-banner[role=status]", /Confirm your email/
  end

  test "the sample quote says visits for more than one" do
    as_business(@business) do
      CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45")
      CatalogItem.create!(name: "Edging", unit: "visit", unit_price: "20")
    end
    get admin_sample_quote_path
    assert_select ".quote-doc-lines td", /\A1\s+visit\z/
    assert_select ".quote-doc-lines td", /\A2\s+visits\z/
  end

  test "My day names today without the year, and the zone once" do
    get admin_my_day_path
    assert_select ".page-lede", "#{@business.today.strftime("%A, %B %-d")} · Times in Eastern Time (US & Canada)"
  end
end
