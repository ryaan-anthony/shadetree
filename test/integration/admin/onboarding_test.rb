require "test_helper"

# ACC-05: the setup checklist, returning to it, the sample quote, the metric and the welcome.
# #289: four steps (services, a client, the first quote, getting paid online) on Home.
class Admin::OnboardingTest < ActionDispatch::IntegrationTest
  setup do
    IndustryPreset.sync!
    @business = businesses(:one)
    @business.update!(industry: "landscaping", phone: nil, onboarded_at: nil)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def step(key) = css_select("#setup-#{key}").first

  test "a new business sees the checklist, ticking from real data" do
    post admin_business_path, params: { business: { name: "Fresh Start Lawns", industry: "landscaping" } }
    follow_redirect!
    assert_select "h2", /Get set up/
    assert_select ".card", /0 of 4 done/
    assert_select "#setup-checklist[data-tour=checklist] progress[max='4'][value='0']" # ACC-08's tour points here
    assert_equal %w[setup-services setup-client setup-quote setup-payments], css_select("#setup-checklist li[id^=setup-]").map { _1["id"] }
    assert_select "#setup-services form[action=?] button", admin_catalog_presets_path, /Add \d+ starter services/
    assert_select "#setup-payments a[href=?]", admin_payment_account_path, "Set up payments"
  end

  test "each step opens the real feature and comes back" do
    get admin_root_path
    # The details a quote needs come first, inside the quote step.
    assert_select "#setup-quote a[href=?]", edit_admin_business_path(from: "setup"), "Add your details first"
    get edit_admin_business_path(from: "setup")
    assert_select "input[name=from][value=setup]"
    patch admin_business_path, params: { from: "setup", business: { phone: "555-0100", email: "a@example.com", address_line1: "1 Main St" } }
    assert_redirected_to admin_root_path

    # Starter services in one action, back to the checklist.
    names = IndustryPreset.for("landscaping").item_list.map(&:name)
    post admin_catalog_presets_path, params: { industry: "landscaping", from: "setup", names: }
    assert_redirected_to admin_root_path
    assert_equal names.size, as_business(@business) { CatalogItem.count }

    post admin_clients_path, params: { from: "setup", client: { display_name: "Maria Lopez", contact_methods_attributes: { "0" => { kind: "phone", value: "5550100100" } } } }
    assert_redirected_to admin_root_path
    get admin_root_path
    assert_select "#setup-client .sr-only", "Done:"
    assert_select "#setup-quote a[href=?]", new_admin_quote_path(from: "setup")
  end

  test "the first quote and online payments complete it; the time to first quote is recorded" do
    travel_to(@business.created_at + 2.hours) do
      as_business(@business) do
        @business.update!(phone: "555-0100", address_line1: "1 Main St")
        client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
        CatalogItem.create!(name: "Mowing", unit_price: "40")
        quote = Quote.start(client:)
        quote.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "40" } ])
        quote.save!
        quote.mark_sent!(by: users(:one), channel: "link")
      end
    end
    assert_in_delta 2.hours.to_i, @business.reload.seconds_to_first_quote, 1
    get admin_root_path
    assert_select "#setup-quote .sr-only", "Done:"
    assert_select "#setup-payments .sr-only", 0, "still to do: getting paid online"
    as_business(@business) { PaymentAccount.create!(account_id: "acct_test1", details_submitted: true, charges_enabled: true, payouts_enabled: true) }
    get admin_root_path
    assert_select "h2", { text: /Get set up/, count: 0 }
    # Finished is remembered: clearing a detail later doesn't bring it back.
    assert @business.reload.onboarded_at
    @business.update!(address_line1: nil)
    get admin_root_path
    assert_select "h2", { text: /Get set up/, count: 0 }
  end

  test "starter services come without prices, so the step asks for them next" do
    as_business(@business) { CatalogItem.create!(name: "Mowing") }
    get admin_root_path
    assert_select "#setup-services a[href=?]", admin_catalog_items_path, "Set your prices"
    as_business(@business) { CatalogItem.first.update!(unit_price: "40") }
    get admin_root_path
    assert_select "#setup-services .sr-only", "Done:"
  end

  test "each member can hide the checklist for themselves, and show it again" do
    patch admin_dismiss_setup_path
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_select "h2", { text: /Get set up/, count: 0 }
    assert_nil @business.reload.onboarded_at

    admin = member_with_role(:admin)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_select "h2", /Get set up/

    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    patch admin_show_setup_path
    follow_redirect!
    assert_select "h2", /Get set up/
  end

  test "/admin/setup, an address people guess, opens the checklist on Home" do
    get "/admin/setup"
    assert_redirected_to "/admin#setup-checklist"
  end

  test "an Admin sees the payments step but the owner sets it up" do
    sign_in member_with_role(:admin)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_select "#setup-payments", /The owner sets this up/
    assert_select "#setup-payments a", 0
  end

  test "the sample quote shows the client page with branding and saves nothing" do
    counts = -> { as_business(@business) { [ Quote.count, Client.count, Property.count, ClientLink.count, UsageEvent.count ] } }
    before = counts.call
    get admin_sample_quote_path
    assert_response :success
    assert_select ".banner", /Sample quote/
    assert_select ".quote-doc-title", IndustryPreset.for("landscaping").item_list.first.name
    assert_select ".quote-doc-meta", /Jordan Rivera/
    assert_select ".quote-doc-lines tbody tr", 3
    assert_select "header.client-head", /#{@business.name}/
    assert_equal before, counts.call
  end

  test "only Owners and Admins see the checklist and the sample; technicians get a welcome on My day" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_sample_quote_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch admin_dismiss_setup_path }

    tech = member_with_role(:technician)
    sign_in tech
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_redirected_to admin_my_day_path
    follow_redirect!
    assert_select "h2", { text: /Get set up/, count: 0 }
    assert_select "h2", /Welcome to #{@business.name}/
    patch admin_dismiss_welcome_path
    get admin_my_day_path
    assert_select "h2", { text: /Welcome to/, count: 0 }
  end
end
