require "test_helper"

class BusinessTest < ActiveSupport::TestCase
  test "requires a name and an owner" do
    business = Business.new

    assert_not business.valid?
    assert_includes business.errors[:name], "can't be blank"
    assert_includes business.errors[:owner], "must exist"
  end

  test "validates email, brand color, currency and industry formats" do
    business = businesses(:one)
    business.assign_attributes(email: "nope", brand_color: "green", currency: "XYZ", industry: "rocketry")

    assert_not business.valid?
    assert_equal %i[brand_color currency email industry], business.errors.attribute_names.sort
  end

  test "creating a business makes its creator an owner" do
    business = Business.create!(name: "Fernhill Cleaning", owner: users(:two))

    assert_equal "owner", business.user_role(users(:two))
  end

  test "defaults the brand color" do
    business = Business.create!(name: "Fernhill Cleaning", owner: users(:two), brand_color: "")

    assert_equal Branding::DEFAULT_COLOR, business.brand_color
  end

  test "new members default to technician" do
    businesses(:one).add_user(users(:unconfirmed))

    assert_equal "technician", businesses(:one).user_role(users(:unconfirmed))
  end

  test "removing a user ends their membership" do
    businesses(:two).remove_user(users(:one))

    assert_not users(:one).member_of?(businesses(:two))
  end
end
