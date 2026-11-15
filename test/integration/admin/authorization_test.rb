require "test_helper"

class Admin::AuthorizationTest < ActionDispatch::IntegrationTest
  test "business settings: owners and admins only" do
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_business_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      patch admin_business_path, params: { business: { name: "Renamed" } }
    end
  end

  test "dashboard and switching: any member" do
    assert_permission_matrix(owner: true, admin: true, technician: true) { get admin_root_path }
  end

  test "technicians don't see settings in the navigation or the setup checklist" do
    sign_in member_with_role(:technician)
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    get admin_root_path
    assert_select "a.side-link[href='#{edit_admin_business_path}']", count: 0
    assert_select ".card-title", text: "Get your business ready", count: 0
  end

  test "denials render a consistent page and log ids, not personal data" do
    user = member_with_role(:technician)
    sign_in user
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    logs = capture_log { get edit_admin_business_path }
    assert_response :forbidden
    assert_select ".empty-title", /isn't available with your role/
    assert_match(/\[authz\] denied admin\/businesses#edit permission=:business_settings user=#{user.id}/, logs)
    assert_no_match user.email, logs
  end

  test "actions without a rule are denied" do
    controller = Class.new(Admin::BaseController) { def show = head(:ok) }
    stub_const = "UnruledTestController"
    Admin.const_set(stub_const, controller)
    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw { get "/admin/unruled", to: "admin/unruled_test#show" }
    sign_in users(:one)
    get "/admin/unruled"
    assert_response :forbidden
  ensure
    Admin.send(:remove_const, stub_const) if Admin.const_defined?(stub_const)
    Rails.application.routes.disable_clear_and_finalize = false
    Rails.application.reload_routes!
  end

  test "unknown permissions fail at class load" do
    assert_raises(Permissions::UnknownPermission) { Class.new(Admin::BaseController) { requires_permission :fly } }
  end

  private

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    previous = Rails.logger
    Rails.logger = logger
    yield
    io.string
  ensure
    Rails.logger = previous
  end
end
