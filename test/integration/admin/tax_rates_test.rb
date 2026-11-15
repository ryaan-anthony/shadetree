require "test_helper"

# CAT-04: the Taxes settings tab.
class Admin::TaxRatesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def rate(name = "State", percent = "6.25", business: @business) = as_business(business) { TaxRate.create!(name:, percent:) }

  test "only owners and admins manage tax rates" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_tax_rates_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_tax_rates_path, params: { tax_rate: { name: "State", percent: "5" } } }
  end

  test "no rates explains that documents show no tax" do
    get admin_tax_rates_path
    assert_select "nav.tabs a[aria-current=page]", "Taxes"
    assert_select "main", /Quotes and invoices show no tax/
  end

  test "adding, editing and archiving a rate" do
    post admin_tax_rates_path, params: { tax_rate: { name: "State", percent: "6.25", applies_by_default: "1" } }
    assert_redirected_to admin_tax_rates_path
    state = as_business(@business) { TaxRate.find_by!(name: "State") }
    assert_equal BigDecimal("6.25"), state.percent
    follow_redirect!
    assert_select "#tax-rate-#{state.uid}", /State.*Default.*6\.25%/m

    get edit_admin_tax_rate_path(state)
    assert_select "input#tax_rate_percent[value='6.25']"
    patch admin_tax_rate_path(state), params: { tax_rate: { percent: "7", applies_by_default: "0" } }
    assert_equal [ BigDecimal("7"), false ], state.reload.then { [ _1.percent, _1.applies_by_default ] }
    follow_redirect!
    assert_select "main", /No rate is a default/

    patch archive_admin_tax_rate_path(state)
    assert state.reload.archived?
    follow_redirect!
    assert_select "#tax-rate-#{state.uid} form[action=?]", restore_admin_tax_rate_path(state)

    assert_select "button[aria-label='Restore State 7%']"
    patch restore_admin_tax_rate_path(state)
    assert_not state.reload.archived?
  end

  test "invalid input re-renders with the typed value" do
    post admin_tax_rates_path, params: { tax_rate: { name: "", percent: "6.12345" } }
    assert_response :unprocessable_content
    assert_select "input#tax_rate_percent[value='6.12345'][aria-invalid=true]"
    assert_select ".error-text", /4 decimal places/
  end

  test "restoring a rate whose name is taken explains why" do
    old = rate("State", "5")
    as_business(@business) { old.archive! }
    rate("State", "6")
    patch restore_admin_tax_rate_path(old)
    assert_redirected_to admin_tax_rates_path
    assert_equal "Name is already used by another tax rate", flash[:alert]
    assert old.reload.archived?
  end

  test "another business's rates are not reachable" do
    theirs = rate("Theirs", "5", business: businesses(:two))
    assert_not_found_across_businesses { get edit_admin_tax_rate_path(theirs) }
    assert_not_found_across_businesses { patch admin_tax_rate_path(theirs), params: { tax_rate: { percent: "1" } } }
    assert_not_found_across_businesses { patch archive_admin_tax_rate_path(theirs) }
    assert_not_found_across_businesses { patch restore_admin_tax_rate_path(theirs) }
    assert_equal BigDecimal("5"), theirs.reload.percent
  end
end
