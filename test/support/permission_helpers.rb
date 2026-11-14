# The shared way to test the role matrix for an action (ACC-04).
#
#   test "only owners and admins can edit settings" do
#     assert_permission_matrix(owner: true, admin: true, technician: false) do
#       get edit_admin_business_path
#     end
#   end
#
# Each role gets a fresh user and membership in one business; the block runs signed in as that
# user. Allowed means anything except 403 (and, for a member, not bounced to sign-in).
module PermissionHelpers
  def member_with_role(role, business: businesses(:one))
    user = User.create!(email: "#{role}-#{SecureRandom.hex(4)}@example.com", password: "password123",
                        first_name: role.to_s.capitalize, confirmed_at: Time.current)
    BusinessUser.create!(user:, business:, role: role.to_s)
    user
  end

  def assert_permission_matrix(business: businesses(:one), **expected, &request)
    unknown = expected.keys.map(&:to_s) - BusinessUser::ROLES
    raise ArgumentError, "Unknown roles #{unknown}" if unknown.any?

    expected.each do |role, allowed|
      user = member_with_role(role, business:)
      sign_in user
      post switch_admin_business_path, params: { business: business.uid }
      instance_exec(&request)
      if allowed
        assert_not_equal 403, response.status, "#{role} should be allowed"
        assert_not_equal new_user_session_url, response.location, "#{role} was sent to sign in"
      else
        assert_response :forbidden, "#{role} should be denied"
      end
      sign_out user
    end
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) { include PermissionHelpers }
