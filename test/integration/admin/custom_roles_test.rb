require "test_helper"

# ACC-07: roles a business builds from the permission catalog, assigned like the built-in ones.
class Admin::CustomRolesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def create_role(name: "Dispatcher", permissions: %w[schedule field_work])
    post admin_roles_path, params: { role: { name:, permissions: [ "" ] + permissions } }
    as_business(@business) { Role.find_by(name:) }
  end

  def member_with_custom_role(role)
    user = User.create!(email: "custom-#{SecureRandom.hex(4)}@example.com", password: "password123", first_name: "Casey", confirmed_at: Time.current)
    BusinessUser.create!(user:, business: @business, role: "custom", role_id: role.id)
    user
  end

  def as_member(user)
    sign_out :user
    sign_in user
    post switch_admin_business_path, params: { business: @business.uid }
  end

  # One page per grantable permission.
  PAGES = { office: :admin_clients_path, schedule: :admin_schedule_path, field_work: :admin_my_day_path,
            business_settings: :edit_admin_business_path, manage_team: :admin_team_path }.freeze

  test "the catalog shows every role's permissions in plain words, grouped; built-ins are read-only" do
    get admin_roles_path
    assert_response :success
    %w[owner admin technician].each { assert_select "#role-#{_1}" }
    assert_select "#role-owner", /Owner only/
    assert_select "#role-admin a[href=?]", new_admin_role_path(from: "admin"), text: "Duplicate"
    assert_select "#role-owner a", text: "Duplicate", count: 0
    Permissions::GROUPS.each_key { assert_select "#role-admin dt", text: _1 }
  end

  test "only Owners manage roles" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: false, technician: false) { get admin_roles_path }
  end

  test "create from a built-in role, edit, and the history records it" do
    get new_admin_role_path(from: "admin")
    assert_select "input[name='role[name]'][value=?]", "Admin (copy)"
    assert_select "input#permission_office[checked]"
    role = create_role
    assert_equal %w[field_work schedule], role.permissions
    patch admin_role_path(role), params: { role: { name: "Dispatch", permissions: [ "", "schedule" ] } }
    assert_redirected_to admin_roles_path
    assert_equal [ "Dispatch", %w[schedule] ], [ role.reload.name, role.permissions ]
    get edit_admin_role_path(role)
    assert_select "li", /Renamed from Dispatcher\. No longer: Work their own assigned visits/
    assert_select "li", /Created with 2 permissions/
  end

  test "Owner-only permissions, built-in names and empty roles are refused" do
    create_role(name: "Boss", permissions: %w[billing office])
    assert_response :unprocessable_content
    create_role(name: "admin", permissions: %w[office])
    assert_select ".error-text", /built-in role/
    create_role(name: "Nothing", permissions: [])
    assert_response :unprocessable_content
    assert_equal 0, as_business(@business) { Role.count }
  end

  test "each permission is enforced through a custom role, and nothing more is granted" do
    PAGES.each do |permission, page|
      as_member(@owner)
      role = create_role(name: "Only #{permission}", permissions: [ permission.to_s ])
      user = member_with_custom_role(role)
      as_member(user)
      PAGES.each do |other, other_page|
        get public_send(other_page)
        if other == permission
          assert_not_equal 403, response.status, "#{permission} should allow #{other_page}"
        else
          assert_response :forbidden, "#{permission} shouldn't allow #{other_page}"
        end
      end
      get admin_roles_path
      assert_response :forbidden, "custom roles never manage roles (Owner-only)"
      get admin_plan_path
      assert_response(:forbidden) unless permission == :business_settings
    end
  end

  test "custom roles are given from the team page and in invitations, and take effect on the next request" do
    role = create_role
    tech = member_with_role(:technician)
    membership = @business.business_users.find_by!(user: tech)
    patch admin_member_path(membership), params: { member: { role: role.choice } }
    assert_redirected_to admin_team_path
    assert_equal [ "custom", role.id ], membership.reload.slice(:role, :role_id).values
    assert_match "is now a Dispatcher", flash[:notice]
    get admin_team_path
    assert_select "#member-#{membership.uid} option[selected][value=?]", role.choice

    perform_enqueued_jobs { post admin_invitations_path, params: { invitation: { email: "new@example.com", role: role.choice } } }
    invitation = as_business(@business) { Invitation.find_by!(email: "new@example.com") }
    assert_equal role.id, invitation.role_id
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "as a dispatcher"

    as_member(tech)
    get admin_schedule_path
    assert_response :success
    as_member(@owner)
    patch admin_role_path(role), params: { role: { name: "Dispatcher", permissions: [ "", "field_work" ] } }
    as_member(tech)
    get admin_schedule_path
    assert_response :forbidden, "the change applies on the next request"
  end

  test "Admins can give custom roles but never Owner; another business's role can't be given" do
    role = create_role
    theirs = as_business(businesses(:two)) { Role.create!(name: "Theirs", permissions: %w[office]) }
    admin = member_with_role(:admin)
    tech = member_with_role(:technician)
    membership = @business.business_users.find_by!(user: tech)
    as_member(admin)
    patch admin_member_path(membership), params: { member: { role: role.choice } }
    assert_equal role.id, membership.reload.role_id
    patch admin_member_path(membership), params: { member: { role: theirs.choice } }
    assert_equal role.id, membership.reload.role_id, "another business's role is refused"
    post admin_invitations_path, params: { invitation: { email: "x@example.com", role: theirs.choice } }
    assert_nil Invitation.unscoped.find_by(email: "x@example.com")
  end

  test "deleting a role in use asks where its members go, and moves them and pending invitations" do
    role = create_role
    other = create_role(name: "Lead tech", permissions: %w[office field_work])
    user = member_with_custom_role(role)
    post admin_invitations_path, params: { invitation: { email: "new@example.com", role: role.choice } }
    get delete_admin_role_path(role)
    assert_select "select#replacement option[value=?]", other.choice
    delete admin_role_path(role), params: { replacement: other.choice }
    assert_redirected_to admin_roles_path
    assert_not Role.unscoped.exists?(role.id)
    assert_equal other.id, @business.business_users.find_by!(user:).role_id
    assert_equal other.id, as_business(@business) { Invitation.find_by!(email: "new@example.com").role_id }
    assert as_business(@business) { RoleEvent.exists?(kind: "deleted") }
  end

  test "on a plan without custom roles, existing ones keep working but can't be changed or newly given" do
    role = create_role
    user = member_with_custom_role(role)
    tech = member_with_role(:technician)
    @business.update!(plan_overrides: { "limits" => { "team_members" => nil } })

    get admin_roles_path
    assert_select ".banner", /keep working/
    get new_admin_role_path
    assert_redirected_to admin_roles_path
    patch admin_role_path(role), params: { role: { name: "Changed", permissions: [ "", "office" ] } }
    assert_equal "Dispatcher", role.reload.name
    patch admin_member_path(@business.business_users.find_by!(user: tech)), params: { member: { role: role.choice } }
    assert_equal "technician", @business.business_users.find_by!(user: tech).role
    assert_match "aren't included", flash[:alert]

    membership = @business.business_users.find_by!(user: user)
    patch deactivate_admin_member_path(membership)
    assert_not membership.reload.active?, "a member with a custom role can still be deactivated"
    patch reactivate_admin_member_path(membership)
    assert membership.reload.active?

    as_member(user)
    get admin_schedule_path
    assert_response :success, "the role still works"
  end

  test "accepting an invitation with a custom role gives that role; the sidebar names it" do
    role = create_role
    invitation = as_business(@business) { Invitation.create!(email: "casey@example.com", role: "custom", role_id: role.id, invited_by: @owner) }
    user = User.create!(email: "casey@example.com", password: "password123", first_name: "Casey", confirmed_at: Time.current)
    membership = invitation.accept!(user)
    assert_equal [ "custom", role.id ], membership.slice(:role, :role_id).values
    as_member(user)
    get admin_my_day_path
    assert_select ".side-foot, aside", /Dispatcher/
    assert_select "p", /on the team as a dispatcher/
  end

  test "notifications follow a custom role's permissions" do
    role = create_role(name: "Office", permissions: %w[office])
    user = member_with_custom_role(role)
    assert_includes NotificationType.for(@business.business_users.find_by!(user:)).map(&:kind), "new_request"
    assert_not_includes NotificationType.for(@business.business_users.find_by!(user: member_with_custom_role(create_role))).map(&:kind), "new_request"
  end
end
