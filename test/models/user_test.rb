require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires a unique email" do
    user = User.new(email: users(:one).email, password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "full name falls back to email" do
    assert_equal "John Doe", users(:one).full_name
    assert_equal "a@example.com", User.new(email: "a@example.com").full_name
  end

  test "memberships and owned businesses" do
    user = users(:one)

    assert_includes user.businesses, businesses(:one)
    assert_includes user.businesses, businesses(:two)
    assert_equal [ businesses(:one) ], user.owned_businesses.to_a
  end

  test "role and membership checks are per business" do
    user = users(:one)

    assert user.owner_of?(businesses(:one))
    assert_not user.owner_of?(businesses(:two))
    assert user.member_of?(businesses(:two))
    assert_equal "technician", user.role_in(businesses(:two))
    assert_nil users(:unconfirmed).role_in(businesses(:one))
  end

  test "inactive memberships don't count" do
    business_users(:one_member_of_two).update!(active: false)

    assert_not users(:one).member_of?(businesses(:two))
  end

  test "destroying a user removes their memberships and owned businesses" do
    user = users(:one)

    assert_difference -> { Business.count } => -1, -> { BusinessUser.count } => -2 do
      user.destroy
    end
  end
end
