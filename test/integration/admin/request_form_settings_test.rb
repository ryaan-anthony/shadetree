require "test_helper"

# CLI-03: the request form's settings: on/off, intro text, the link name, link and QR code.
class Admin::RequestFormSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "only Owners and Admins can change the form or get its QR code" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_business_path(tab: "request_form") }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get request_form_qr_admin_business_path }
  end

  test "the tab shows the link to copy and saves the form settings" do
    get edit_admin_business_path(tab: "request_form")
    assert_select "input[type=hidden][value=?]", public_request_url("one-biz")
    assert_select "a[href=?]", request_form_qr_admin_business_path

    patch admin_business_path(tab: "request_form"), params: { business: { request_form_enabled: "0", request_form_intro: "  We reply fast. ", handle: "Oakline-Lawn" } }
    assert_redirected_to edit_admin_business_path(tab: "request_form")
    @business.reload
    assert_equal [ false, "We reply fast.", "oakline-lawn" ], [ @business.request_form_enabled, @business.request_form_intro, @business.handle ]
  end

  test "link names must be well-formed, free and not reserved" do
    [ [ "two-biz", /has already been taken/ ], [ "admin", /is reserved/ ], [ "no spaces!", /lowercase letters, digits or dashes/ ], [ "ab", /3 to 40/ ] ].each do |handle, error|
      patch admin_business_path(tab: "request_form"), params: { business: { handle: } }
      assert_response :unprocessable_content
      assert_select ".error-text", error
    end
    assert_equal "one-biz", @business.reload.handle
  end

  test "the QR code is a PNG of the link" do
    get request_form_qr_admin_business_path
    assert_response :success
    assert_equal "image/png", response.media_type
    assert response.body.start_with?("\x89PNG".b)
    assert_match "one-biz-request-form-qr.png", response.headers["Content-Disposition"]
  end

  test "new businesses get a free link name from their name" do
    post admin_business_path, params: { business: { name: "Test Business One", industry: "landscaping" } }
    business = Business.order(:id).last
    assert_equal "test-business-one", business.handle
    assert_equal "test-business-one-2", Business.create!(name: "Test Business One!", owner: users(:one), plan: plans(:starter)).handle
    assert_equal "joe-s-lawn", Business.create!(name: "Joe_s Lawn", owner: users(:one), plan: plans(:starter)).handle
  end
end
