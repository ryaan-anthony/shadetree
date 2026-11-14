require "test_helper"

class Admin::BusinessesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.new(
      email: "business_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @user.skip_confirmation_notification!
    @user.save!

    sign_in @user
  end

  teardown do
    Business.destroy_all
    User.destroy_all
  end

  # NEW ACTION TESTS

  test "should display business creation form" do
    get new_admin_business_path
    assert_response :success
    assert_select "h1", /Set up your business|Create another business/
  end

  test "unauthenticated user cannot access new business form" do
    sign_out @user
    get new_admin_business_path
    assert_redirected_to new_user_session_path
  end

  # CREATE ACTION TESTS

  test "should create business with valid data" do
    assert_difference("Business.count") do
      post admin_business_path, params: {
        business: {
          name: "Test Business",
          industry: "landscaping"
        }
      }
    end

    business = Business.last
    assert_equal "Test Business", business.name
    assert_equal "landscaping", business.industry
    assert_equal @user.id, business.owner_id
    assert_redirected_to admin_root_path
    assert_equal "Test Business is ready.", flash[:notice]
  end

  test "should require an industry at setup (ACC-02)" do
    assert_no_difference("Business.count") do
      post admin_business_path, params: { business: { name: "Minimal Business" } }
    end
    assert_response :unprocessable_content
    assert_select "#business_industry[aria-invalid='true']"
  end

  test "should reject business without name" do
    assert_no_difference("Business.count") do
      post admin_business_path, params: {
        business: {
          name: "",
          industry: "landscaping"
        }
      }
    end

    assert_response :unprocessable_content
    assert_select "#business_name[aria-invalid='true']"
  end

  test "should reject invalid industry" do
    assert_no_difference("Business.count") do
      post admin_business_path, params: {
        business: {
          name: "Test Business",
          industry: "invalid_industry"
        }
      }
    end

    assert_response :unprocessable_content
  end

  # EDIT ACTION TESTS

  test "should display business edit form" do
    business = Business.create!(
      name: "Existing Business",
      owner: @user
    )

    get edit_admin_business_path
    assert_response :success
    assert_match /Business Profile|Basic Information/i, response.body
  end

  test "cannot edit without business" do
    get edit_admin_business_path
    assert_redirected_to new_admin_business_path
  end

  # UPDATE ACTION TESTS

  test "should update business with valid data" do
    business = Business.create!(
      name: "Original Name",
      owner: @user
    )

    patch admin_business_path, params: {
      business: {
        name: "Updated Name",
        email: "updated@example.com",
        phone: "555-1234",
        industry: "maintenance"
      }
    }

    business.reload
    assert_equal "Updated Name", business.name
    assert_equal "updated@example.com", business.email
    assert_equal "maintenance", business.industry
    assert_redirected_to edit_admin_business_path
    assert_match /updated successfully/i, flash[:notice]
  end

  test "should reject update with blank name" do
    business = Business.create!(
      name: "Original Name",
      owner: @user
    )

    patch admin_business_path, params: {
      business: {
        name: ""
      }
    }

    assert_response :unprocessable_content
    business.reload
    assert_equal "Original Name", business.name
  end

  # AUTHORIZATION TESTS

  test "user can only manage their own business" do
    other_user = User.new(
      email: "other@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    other_user.skip_confirmation_notification!
    other_user.save!

    other_business = Business.create!(
      name: "Other Business",
      owner: other_user
    )

    # Current user creates their own business
    post admin_business_path, params: {
      business: { name: "My Business" }
    }

    # Should create a new business for current user, not affect other's
    assert_not_equal "My Business", other_business.reload.name
  end
end
