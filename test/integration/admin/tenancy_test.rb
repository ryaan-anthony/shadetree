require "test_helper"

# Current business resolution for staff requests (PLT-06).
class Admin::TenancyTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one) # owner of business one, technician in business two
    sign_in @user
  end

  test "the session's business is used only while the membership is active" do
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_equal businesses(:two).id, session[:current_business_id]

    business_users(:one_member_of_two).update!(active: false)
    get admin_root_path
    assert_response :success
    assert_equal businesses(:one).id, session[:current_business_id]
  end

  test "a business id planted in the session is ignored without a membership" do
    other = Business.create!(name: "Not mine", owner: users(:two))
    post switch_admin_business_path, params: { business: other.uid }
    assert_redirected_to admin_root_path
    assert_not_equal other.id, session[:current_business_id]
  end

  test "switching by sequential id no longer works" do
    post switch_admin_business_path, params: { business: businesses(:two).id }
    assert_equal "That business isn't available to you.", flash[:alert]
  end

  test "creating a business makes it current" do
    post admin_business_path, params: { business: { name: "Fresh Start" } }
    assert_equal Business.find_by!(name: "Fresh Start").id, session[:current_business_id]
  end

  test "settings show the current business, not merely the newest membership" do
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    get edit_admin_business_path
    assert_select "input[value='#{businesses(:one).name}']"
  end

  test "request context doesn't leak past the request" do
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    get admin_root_path
    assert_nil Current.business
    assert_equal "UTC", Time.zone.name
  end
end
