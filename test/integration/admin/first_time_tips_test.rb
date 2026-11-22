require "test_helper"

# ACC-08: a first-time tip on each main page, once per person per business, for the pages their
# role can use; shown again from Help, turned off in Your account, never marked by support.
class Admin::FirstTimeTipsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @membership = business_users(:one)
    sign_in users(:one)
  end

  PAGES = {
    "requests" => -> { admin_service_requests_path },
    "quote_builder" => -> { new_admin_quote_path },
    "schedule" => -> { admin_schedule_path },
    "invoices" => -> { admin_invoices_path },
    "services" => -> { admin_catalog_items_path },
    "settings" => -> { edit_admin_business_path }
  }.freeze

  test "each main page has its tip until it's been shown; hiding it is recorded too" do
    PAGES.each do |key, path|
      get instance_exec(&path)
      assert_select "#tip-#{key}[role=note][hidden][data-controller=tip]", 1, key
    end
    quote = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Quote.start(client:).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
        _1.save!
      end
    end
    get new_admin_quote_send_path(quote)
    assert_select "#tip-send", 1
    get admin_root_path
    assert_select ".tip", 0, "Home has the tour instead"

    patch admin_tip_path("requests"), params: { event: "seen" }, as: :json
    assert_response :no_content
    seen_at = @membership.reload.tips.dig("requests", "seen_at")
    assert seen_at
    patch admin_tip_path("requests"), params: { event: "seen" }, as: :json
    patch admin_tip_path("requests"), params: { event: "dismissed" }, as: :json
    assert_equal seen_at, @membership.reload.tips.dig("requests", "seen_at"), "the first time is kept"
    assert @membership.tips.dig("requests", "dismissed_at")
    get admin_service_requests_path
    assert_select ".tip", 0, "once per person"

    sign_in users(:two) # the same page in another business, as someone else, still has it
    get admin_service_requests_path
    assert_select "#tip-requests", 1
  end

  test "Help shows them again; Your account turns them off and on" do
    @membership.update!(tips: FirstTimeTips::KEYS.index_with { { "seen_at" => Time.current.iso8601 } })
    get admin_service_requests_path
    assert_select ".tip", 0
    assert_select "#help-menu ~ .menu form[action=?] button", admin_tips_path, text: /Show tips again/
    delete admin_tips_path, headers: { "HTTP_REFERER" => admin_service_requests_url }
    assert_redirected_to admin_service_requests_url
    assert_equal "Tips will show again the first time you open each page.", flash[:notice]
    assert_empty @membership.reload.tips
    follow_redirect!
    assert_select "#tip-requests"

    get edit_user_registration_path
    assert_select "#tips-setting", /A short tip shows/
    patch admin_tips_preference_path, params: { off: true }
    assert_redirected_to edit_user_registration_path
    assert users(:one).reload.tips_off?
    get admin_service_requests_path
    assert_select ".tip", 0, "off for this person"
    patch admin_tips_preference_path, params: { off: false }
    assert_not users(:one).reload.tips_off?
  end

  test "only tips for pages the role can use" do
    office_only = as_business(@business) { Role.create!(name: "Office help", permissions: %w[office]) }
    user = User.create!(email: "office@example.com", password: "password123", first_name: "Office", confirmed_at: Time.current)
    membership = BusinessUser.create!(business: @business, user:, role: "custom", role_id: office_only.id)
    assert_equal "requests", FirstTimeTips.for(membership, "admin/service_requests", "index")
    assert_nil FirstTimeTips.for(membership, "admin/catalog_items", "index")
    assert_nil FirstTimeTips.for(membership, "admin/schedule", "show")
    assert_nil FirstTimeTips.for(membership, "admin/quotes", "show"), "only the pages listed"

    patch admin_tip_path("requests"), params: { event: "shown_twice" }, as: :json
    assert_response :unprocessable_content
  end

  test "support viewing as the member sees tips but never marks, resets or turns them off" do
    owner = business_users(:two)
    owner.update!(tips: { "requests" => { "seen_at" => Time.current.iso8601 } })
    sign_in_operator
    post ops_business_impersonation_path(businesses(:two)), params: { member: owner.uid, reason: "Ticket: walking through setup" }
    get admin_invoices_path
    assert_select "#tip-invoices[data-tip-record-value=false]"

    patch admin_tip_path("invoices"), params: { event: "seen" }, as: :json
    assert_response :forbidden
    delete admin_tips_path
    assert_match "read-only", flash[:alert]
    patch ops_impersonation_path, params: { mode: "write", reason: "Fixing their settings with them" }
    patch admin_tips_preference_path, params: { off: true }
    assert_match "Support can't change this", flash[:alert]
    assert_equal [ "requests" ], owner.reload.tips.keys
    assert_not users(:two).reload.tips_off?
  end
end
