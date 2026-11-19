require "test_helper"

# OPS-03: every staff and account page says what Shadetree support may do there while viewing
# the app as a member, so a new controller can't be open to it by accident.
class ImpersonationDeclarationsTest < ActiveSupport::TestCase
  test "every admin, account and invitation controller declares its impersonation access" do
    paths = Rails.application.routes.routes.filter_map { _1.defaults[:controller] }.uniq
                 .select { _1.start_with?("admin/", "users/") || _1 == "invitations" }
    assert paths.size > 40
    undeclared = paths.reject { "#{_1.camelize}Controller".constantize.impersonation_declared? }
    assert_empty undeclared, "Add `impersonation :allowed / :read_only / :blocked` to these controllers"
  end

  test "levels resolve per action, and undeclared means read-only" do
    assert_equal :blocked, Admin::DataExportsController.impersonation_level(:show)
    assert_equal :read_only, Admin::DataExportsController.impersonation_level(:index)
    assert_equal :blocked, Admin::BusinessesController.impersonation_level(:switch)
    assert_equal :allowed, Admin::BusinessesController.impersonation_level(:update)
    assert Admin::ClientsController.impersonation_read?(:search)
    assert_not Admin::ClientsController.impersonation_read?(:create)
    assert_equal :read_only, HomeController.impersonation_level(:index)
  end
end
