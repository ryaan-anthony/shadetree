require "test_helper"

class PermissionsTest < ActiveSupport::TestCase
  test "the role table matches the capability table in 02-accounts" do
    table = File.read(Rails.root.join("docs/plans/02-accounts.md"))
    checked = []
    table.scan(/^\|[^|\n]+\|\s*((?:`\w+`(?:,\s*)?)+)\s*\|\s*(✔?)\s*\|\s*(✔?)\s*\|\s*(✔?)\s*\|\s*$/).each do |permissions, owner, admin, technician|
      permissions.scan(/`(\w+)`/).flatten.each do |permission|
        expected = { "owner" => owner, "admin" => admin, "technician" => technician }.select { |_, mark| mark == "✔" }.keys
        assert_equal expected, Permissions.roles_with(permission), "02-accounts table vs Permissions for #{permission}"
        checked << permission
      end
    end
    # Every permission in code must appear in a parsed row, so a row the pattern misses fails here.
    assert_equal Permissions::CATALOG.keys.map(&:to_s).sort, checked.uniq.sort

    assert_equal Permissions::CATALOG.keys, Permissions::ROLES["owner"]
    assert_equal %w[owner], Permissions.roles_with(:billing)
    assert_equal %w[owner], Permissions.roles_with(:manage_owners)
    assert_equal %w[owner admin], Permissions.roles_with(:manage_team)
    assert_equal %w[owner admin], Permissions.roles_with(:office)
    assert_equal %w[owner admin technician], Permissions.roles_with(:field_work)
    assert_equal %w[owner admin technician], Permissions.roles_with(:quote_requests), "QTE-07 (owner, 2026-11-22)"
    assert_equal %w[owner admin], Permissions.roles_with(:send_own_quotes), "Technicians' quotes are reviewed"
  end

  test "every role is a membership role and unknown permissions raise" do
    assert_equal BusinessUser::ROLES.sort, Permissions::ROLES.keys.sort
    assert_raises(Permissions::UnknownPermission) { Permissions.granted?("owner", :fly) }
  end

  test "inactive memberships grant nothing" do
    membership = business_users(:one)
    assert membership.can?(:billing)
    membership.active = false
    assert_not membership.can?(:field_work)
  end

  test "admins manage the team but not owners; owners manage everyone" do
    business = businesses(:one)
    owner = business_users(:one)
    admin = BusinessUser.create!(business:, user: users(:two), role: "admin")
    tech = BusinessUser.create!(business:, user: users(:unconfirmed), role: "technician")

    assert admin.can_assign_role?(tech, "admin")
    assert_not admin.can_assign_role?(tech, "owner")
    assert_not admin.can_assign_role?(owner, "technician")
    assert owner.can_assign_role?(tech, "owner")
    assert_not tech.can_assign_role?(admin, "technician")
    assert_not owner.can_assign_role?(business_users(:two), "admin"), "other business"
    assert_not owner.can_assign_role?(tech, "superuser")
  end
end
