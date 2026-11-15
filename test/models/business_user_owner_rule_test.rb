require "test_helper"

# ACC-02: a business always has at least one active Owner.
class BusinessUserOwnerRuleTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "only-owner@example.com", password: "password123", first_name: "Olive", confirmed_at: Time.current)
    @business = Business.create!(name: "Solo", owner: @owner)
    @membership = @business.business_users.find_by!(user: @owner)
  end

  test "the last owner can't be demoted, deactivated or removed" do
    assert_not @membership.update(role: "admin")
    assert_match "last owner", @membership.errors.full_messages.to_sentence
    assert_not @membership.reload.update(active: false)
    assert_not @membership.reload.destroy
    assert BusinessUser.exists?(@membership.id)
  end

  test "with a second owner, either can step down" do
    second = BusinessUser.create!(business: @business, user: users(:two), role: "owner")
    assert @membership.update(role: "admin")
    assert_not second.reload.update(role: "technician"), "now second is the last owner"
  end

  test "an inactive owner doesn't count" do
    BusinessUser.create!(business: @business, user: users(:two), role: "owner", active: false)
    assert_not @membership.update(active: false)
  end

  test "deleting the business removes its memberships" do
    assert_difference("BusinessUser.count", -1) { @business.destroy }
  end

  test "a rejected change can't be followed by destroying the same instance" do
    assert_not @membership.update(role: "admin")
    assert_not @membership.destroy, "guard reads the database, not unsaved attributes"
    assert BusinessUser.exists?(@membership.id)
  end

  test "memberships can't move between businesses or users" do
    assert_includes BusinessUser.readonly_attributes, "business_id"
    assert_includes BusinessUser.readonly_attributes, "user_id"
  end

  test "deleting an account removes its own businesses first" do
    assert_difference("Business.count", -1) { @owner.destroy }
  end

  test "an account that is the last owner of someone else's business can't be deleted" do
    member = User.create!(email: "member@example.com", password: "password123", confirmed_at: Time.current)
    theirs = Business.create!(name: "Theirs", owner: users(:two))
    BusinessUser.create!(business: theirs, user: member, role: "owner")
    theirs.business_users.find_by!(user: users(:two)).update!(role: "admin")

    assert_not member.destroy
    assert User.exists?(member.id)
    assert theirs.business_users.active.owners.exists?(user: member)
  end
end
