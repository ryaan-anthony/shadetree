require "test_helper"

class Admin::BusinessOnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.new(
      email: "onboarding_test@example.com",
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
  end

  # ====================
  # NEW ACTION TESTS
  # ====================

  test "should redirect to sign in if not authenticated" do
    sign_out @user
    get new_admin_business_onboarding_path
    assert_redirected_to new_user_session_path
  end

  test "should redirect to sign in if user not confirmed" do
    @user.update_columns(confirmed_at: nil)
    get new_admin_business_onboarding_path
    assert_redirected_to new_user_session_path
  end

  test "should display basics step by default" do
    get new_admin_business_onboarding_path
    assert_response :success
    assert_match /Tell us about your business/i, response.body
  end

  test "should display hours step when specified" do
    get new_admin_business_onboarding_path(step: "hours")
    assert_response :success
    assert_match /operating hours/i, response.body
  end

  test "should display location step when specified" do
    get new_admin_business_onboarding_path(step: "location")
    assert_response :success
    assert_match /service area|location/i, response.body
  end

  test "should display branding step when specified" do
    get new_admin_business_onboarding_path(step: "branding")
    assert_response :success
    assert_match /brand/i, response.body
  end

  test "should redirect to basics for invalid step" do
    get new_admin_business_onboarding_path(step: "invalid_step")
    assert_redirected_to new_admin_business_onboarding_path(step: "basics")
    assert_match /invalid/i, flash[:alert]
  end

  test "should build new business if user has none" do
    get new_admin_business_onboarding_path
    assert_response :success
    assert assigns(:business).new_record?
  end

  test "should load existing business if user has one" do
    business = Business.create!(
      name: "Existing Business",
      email: "existing@example.com",
      owner: @user
    )

    get new_admin_business_onboarding_path
    assert_response :success
    assert_equal business.id, assigns(:business).id
  end

  # ====================
  # BASICS STEP TESTS
  # ====================

  test "should create business with valid basics data" do
    assert_difference("Business.count") do
      post admin_business_onboarding_index_path, params: {
        step: "basics",
        business: {
          name: "Test Landscaping",
          email: "test@landscaping.com",
          phone: "555-1234",
          address: "123 Main St",
          description: "Professional landscaping services",
          website: "https://testlandscaping.com",
          industry: "landscaping"
        }
      }
    end

    business = Business.last
    assert_equal "Test Landscaping", business.name
    assert_equal "test@landscaping.com", business.email
    assert_equal "landscaping", business.industry
    assert_equal @user.id, business.owner_id
    assert_redirected_to new_admin_business_onboarding_path(step: "hours")
  end

  test "should update existing business with basics data" do
    business = Business.create!(
      name: "Original Name",
      email: "original@example.com",
      owner: @user
    )

    assert_no_difference("Business.count") do
      post admin_business_onboarding_index_path, params: {
        step: "basics",
        business: {
          name: "Updated Name",
          email: "updated@example.com",
          phone: "555-5678",
          industry: "maintenance"
        }
      }
    end

    business.reload
    assert_equal "Updated Name", business.name
    assert_equal "updated@example.com", business.email
    assert_equal "maintenance", business.industry
  end

  test "should reject invalid basics data" do
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "",
        email: "invalid_email",
        phone: "555-1234"
      }
    }

    assert_response :unprocessable_content
    assert_match /can't be blank|is invalid/i, response.body
  end

  test "should reject basics with invalid industry" do
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Test Business",
        email: "test@example.com",
        industry: "invalid_industry"
      }
    }

    assert_response :unprocessable_content
  end

  test "should track onboarding step after basics" do
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Test Business",
        email: "test@example.com",
        industry: "landscaping"
      }
    }

    business = Business.last
    assert_equal "basics", business.onboarding_step
  end

  # ====================
  # HOURS STEP TESTS
  # ====================

  test "should update business with hours and timezone" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user
    )

    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/New_York",
      monday_enabled: "1",
      monday_start: "9:00",
      monday_end: "17:00"
    }

    business.reload
    assert_equal "America/New_York", business.timezone
    assert_equal "hours", business.onboarding_step
    assert_redirected_to new_admin_business_onboarding_path(step: "location")
  end

  test "should accept hours step without any days enabled" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user
    )

    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/Chicago"
    }

    business.reload
    assert_equal "America/Chicago", business.timezone
    assert_redirected_to new_admin_business_onboarding_path(step: "location")
  end

  # ====================
  # LOCATION STEP TESTS
  # ====================

  test "should skip location step for now" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user
    )

    post admin_business_onboarding_index_path, params: {
      step: "location",
      business: {}
    }

    business.reload
    assert_equal "location", business.onboarding_step
    assert_redirected_to new_admin_business_onboarding_path(step: "branding")
  end

  # ====================
  # BRANDING STEP TESTS
  # ====================

  test "should update business with branding data" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user,
      onboarding_step: "location"  # Set to location so branding is next, not completion
    )

    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: {
        brand_color: "#1E40AF",
        logo_url: "https://example.com/logo.png"
      }
    }

    business.reload
    assert_equal "#1E40AF", business.brand_color
    assert_equal "https://example.com/logo.png", business.logo_url
    # After submitting branding, onboarding completes
    assert business.onboarded?
    assert_nil business.onboarding_step
  end

  test "should reject invalid brand color format" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user
    )

    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: {
        brand_color: "invalid_color"
      }
    }

    assert_response :unprocessable_content
  end

  test "should complete onboarding after branding step" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user,
      onboarding_step: "branding"
    )

    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: {
        brand_color: "#059669"
      }
    }

    business.reload
    assert business.onboarded?
    assert_not_nil business.onboarded_at
    assert_nil business.onboarding_step
    assert_redirected_to admin_root_path
    assert_match /successfully/i, flash[:notice]
  end

  # ====================
  # STEP PROGRESSION TESTS
  # ====================

  test "should progress through all steps in order" do
    # Step 1: Basics
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Progressive Business",
        email: "progress@example.com",
        industry: "landscaping"
      }
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "hours")

    business = Business.last

    # Step 2: Hours
    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/New_York"
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "location")

    # Step 3: Location
    post admin_business_onboarding_index_path, params: {
      step: "location",
      business: {}
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "branding")

    # Step 4: Branding (final step)
    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: { brand_color: "#059669" }
    }

    business.reload
    assert business.onboarded?
    assert_redirected_to admin_root_path
  end

  # ====================
  # AUTHORIZATION TESTS
  # ====================

  test "should not allow editing another user's business" do
    other_user = User.create!(
      email: "other@example.com",
      password: "password123",
      confirmed_at: Time.current
    )

    other_business = Business.create!(
      name: "Other Business",
      email: "other@business.com",
      owner: other_user
    )

    # Try to update other user's business
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        id: other_business.id,
        name: "Hacked Name",
        email: "hacked@example.com"
      }
    }

    # Should create new business for current user, not update other's
    assert_not_equal "Hacked Name", other_business.reload.name
  end

  # ====================
  # ERROR HANDLING TESTS
  # ====================

  test "should handle missing parameters gracefully" do
    post admin_business_onboarding_index_path, params: {
      step: "basics"
      # Missing business params
    }

    # Rails returns 400 Bad Request for missing required params
    assert_response :bad_request
  end

  test "should handle missing step parameter" do
    post admin_business_onboarding_index_path, params: {
      business: {
        name: "Test",
        email: "test@example.com"
      }
    }

    # Should default to basics step
    assert_redirected_to new_admin_business_onboarding_path(step: "hours")
  end

  # ====================
  # SUCCESS MESSAGE TESTS
  # ====================

  test "should show success message after each step" do
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Test Business",
        email: "test@example.com",
        industry: "landscaping"
      }
    }

    assert_match /saved successfully/i, flash[:notice]
  end

  test "should show welcome message after completion" do
    business = Business.create!(
      name: "Test Business",
      email: "test@example.com",
      owner: @user,
      onboarding_step: "branding"
    )

    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: { brand_color: "#059669" }
    }

    assert_match /welcome to shadetree/i, flash[:notice]
  end
end

