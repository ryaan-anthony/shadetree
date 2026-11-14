require "test_helper"

class BusinessUserTest < ActiveSupport::TestCase
  test "roles are owner, admin and technician" do
    assert_equal %w[owner admin technician], BusinessUser::ROLES

    membership = business_users(:one_member_of_two)
    membership.role = "member"

    assert_not membership.valid?
    assert_includes membership.errors[:role], "is not included in the list"
  end

  test "a person has one membership per business" do
    duplicate = BusinessUser.new(user: users(:one), business: businesses(:one), role: "admin")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "the database also enforces one membership per business" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      BusinessUser.insert!({ user_id: users(:one).id, business_id: businesses(:one).id, role: "admin" })
    end
  end

  test "role helpers" do
    assert business_users(:one).owner?
    assert business_users(:one).can_manage?
    assert_not business_users(:one_member_of_two).can_manage?
    assert_equal [ business_users(:one_member_of_two) ], BusinessUser.technicians.to_a
  end
end
