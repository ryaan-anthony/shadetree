require "test_helper"

# CAT-01: business profile and document defaults.
class Admin::BusinessSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "owners and admins can open settings; technicians can't" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_business_path(tab: "documents") }
  end

  test "Technicians see prices says it covers visits only; quoting shows prices (QTE-07, owner, 2026-11-22)" do
    get edit_admin_business_path(tab: "documents")
    assert_select "label", /Technicians see prices.*On the visits they're sent to.*Technicians drafting a quote see the catalog prices\./m
  end

  test "the business tab edits profile, contact, structured address, time zone and currency" do
    get edit_admin_business_path
    %w[name industry description email phone website address_line1 address_line2 city region postal_code country timezone currency].each do |field|
      assert_select "[name='business[#{field}]']", 1, "missing #{field}"
    end
    assert_select "label[for='business_region']", /\AState/

    patch admin_business_path, params: { business: {
      address_line1: "12 Elm St", city: "Austin", region: "TX", postal_code: "78701", country: "US",
      timezone: "America/Chicago", currency: "USD", website: "oakline.example"
    } }
    assert_redirected_to edit_admin_business_path
    @business.reload
    assert_equal [ "12 Elm St", "Austin, TX 78701" ], @business.address_lines
    assert_equal "https://oakline.example", @business.website
    assert_equal "America/Chicago", @business.timezone
  end

  test "the documents tab sets defaults for new quotes and invoices" do
    patch admin_business_path(tab: "documents"), params: { business: {
      quote_expiry_days: "45", quote_terms: "50% deposit", invoice_due_days: "0", invoice_terms: "Thanks!",
      quote_number_prefix: "est", invoice_number_prefix: "OAK"
    } }
    assert_redirected_to edit_admin_business_path(tab: "documents")
    @business.reload
    assert_equal [ 45, "50% deposit", 0, "Thanks!", "EST", "OAK" ],
                 @business.values_at(:quote_expiry_days, :quote_terms, :invoice_due_days, :invoice_terms, :quote_number_prefix, :invoice_number_prefix)
    assert_equal "EST-0001", @business.next_document_number(:quote)
    assert_equal "OAK-0001", @business.next_document_number(:invoice)
  end

  test "validation errors are shown next to the fields" do
    patch admin_business_path(tab: "documents"), params: { business: { quote_expiry_days: "0", quote_number_prefix: "no spaces!" } }
    assert_response :unprocessable_content
    assert_select "#business_quote_expiry_days[aria-invalid='true']"
    assert_select "#business_quote_number_prefix[aria-invalid='true']"

    patch admin_business_path, params: { business: { country: "ZZ", timezone: "Mars/Base", currency: "JPY", website: "ftp://x" } }
    assert_response :unprocessable_content
    %w[country timezone currency website].each { assert_select "#business_#{_1}[aria-invalid='true']" }
  end

  test "settings only ever change the current business" do
    other = businesses(:two)
    patch admin_business_path, params: { business: { name: "Renamed" }, id: other.uid }
    assert_equal "Renamed", @business.reload.name
    assert_not_equal "Renamed", other.reload.name
  end

  test "new businesses take the browser's time zone and the country's currency" do
    post admin_business_path, params: { business: { name: "Zone Co", industry: "cleaning", timezone: "America/Denver" } }
    assert_equal "America/Denver", Business.find_by!(name: "Zone Co").timezone
    post admin_business_path, params: { business: { name: "Bad Zone Co", industry: "cleaning", timezone: "Nowhere/Land" } }
    assert_nil Business.find_by!(name: "Bad Zone Co").timezone

    assert_equal "CAD", Business.create!(name: "Maple", owner: users(:one), country: "CA", plan: plans(:starter)).currency
    assert_equal "EUR", Business.create!(name: "Dublin", owner: users(:one), country: "IE", plan: plans(:starter)).currency
    assert_equal "USD", Business.create!(name: "Texas", owner: users(:one), plan: plans(:starter)).currency
  end

  test "industries come from data" do
    get edit_admin_business_path
    Industry.all.each { |industry| assert_select "#business_industry option[value='#{industry.key}']", industry.name }
  end

  test "documents copy a snapshot of the business details" do
    snapshot = @business.document_snapshot
    @business.update!(name: "New Name")
    assert_not_equal @business.name, snapshot["name"]
    assert_equal %w[address_lines currency email name phone website], snapshot.keys.sort
  end

  test "the website field accepts a bare domain in the browser and other schemes stay invalid" do
    get edit_admin_business_path(tab: "business")
    assert_select "input#business_website[type=text][inputmode=url]"
    @business.update(website: "ftp://example.com")
    assert_equal "ftp://example.com", @business.website
    assert @business.errors.of_kind?(:website, :invalid)
  end

  test "a Rails time zone name is stored as its identifier and stays selected" do
    @business.update_column(:timezone, "Eastern Time (US & Canada)")
    get edit_admin_business_path(tab: "business")
    assert_select "#business_timezone option[selected][value='America/New_York']"
    @business.update!(timezone: "Eastern Time (US & Canada)")
    assert_equal "America/New_York", @business.timezone
  end

  test "a valid zone without a friendly name is kept as an option" do
    @business.update_column(:timezone, "America/Boise")
    get edit_admin_business_path(tab: "business")
    assert_select "#business_timezone option[selected][value='America/Boise']", "America/Boise"
  end
end
