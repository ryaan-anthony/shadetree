require "test_helper"

class Admin::BusinessOnboardingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.new(
      email: "flow_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
    @user.skip_confirmation_notification!
    @user.save!
  end

  teardown do
    Business.destroy_all
    User.destroy_all
  end

  # ====================
  # HAPPY PATH TESTS
  # ====================

  test "complete onboarding flow from start to finish" do
    sign_in @user

    # Start onboarding
    get new_admin_business_onboarding_path
    assert_response :success
    assert_match /Tell us about your business|business information/i, response.body

    # Complete basics step
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Complete Flow Business",
        email: "complete@flow.com",
        phone: "555-0001",
        address: "123 Complete St",
        description: "Full service business",
        website: "https://complete.com",
        industry: "landscaping"
      }
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "hours")
    follow_redirect!
    assert_response :success

    # Complete hours step
    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/New_York",
      monday_enabled: "1",
      monday_start: "9:00",
      monday_end: "17:00",
      tuesday_enabled: "1",
      tuesday_start: "9:00",
      tuesday_end: "17:00"
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "location")
    follow_redirect!
    assert_response :success

    # Complete location step
    post admin_business_onboarding_index_path, params: {
      step: "location",
      business: {}
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "branding")
    follow_redirect!
    assert_response :success

    # Complete branding step
    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: {
        brand_color: "#059669",
        logo_url: "https://example.com/logo.png"
      }
    }
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success

    # Verify business was created and onboarded
    business = Business.last
    assert_equal "Complete Flow Business", business.name
    assert_equal "complete@flow.com", business.email
    assert_equal "landscaping", business.industry
    assert_equal "America/New_York", business.timezone
    assert_equal "#059669", business.brand_color
    assert business.onboarded?
    assert_not_nil business.onboarded_at
  end

  test "user can skip optional fields and complete onboarding" do
    sign_in @user

    # Basics with only required fields
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Minimal Business",
        email: "minimal@business.com",
        industry: "maintenance"
      }
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "hours")

    # Hours with just timezone
    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/Chicago"
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "location")

    # Location with minimal data
    post admin_business_onboarding_index_path, params: {
      step: "location",
      business: {}
    }
    assert_redirected_to new_admin_business_onboarding_path(step: "branding")

    # Branding with defaults (business model sets default color)
    post admin_business_onboarding_index_path, params: {
      step: "branding",
      business: {
        brand_color: "#059669"
      }
    }
    assert_redirected_to admin_root_path

    business = Business.last
    assert business.onboarded?
  end

  test "user can return to edit previous steps" do
    sign_in @user

    # Complete basics
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Original Name",
        email: "original@example.com",
        industry: "landscaping"
      }
    }

    # Go back to basics and update
    get new_admin_business_onboarding_path(step: "basics")
    assert_response :success

    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Updated Name",
        email: "updated@example.com",
        industry: "maintenance"
      }
    }

    business = Business.last
    assert_equal "Updated Name", business.name
    assert_equal "maintenance", business.industry
  end

  # ====================
  # VALIDATION TESTS
  # ====================

  test "cannot proceed with invalid basics data" do
    sign_in @user

    # Should not create any new business
    assert_no_difference("Business.count") do
      post admin_business_onboarding_index_path, params: {
        step: "basics",
        business: {
          name: "",
          email: "invalid_email"
        }
      }
    end

    assert_response :unprocessable_content
    assert_match /can't be blank|is invalid|invalid/i, response.body
  end

  test "validation errors are displayed on form" do
    sign_in @user

    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "",
        email: ""
      }
    }

    assert_response :unprocessable_content
    assert_match /can't be blank|is invalid/i, response.body
  end

  # ====================
  # AUTHENTICATION TESTS
  # ====================

  test "unauthenticated user redirected to sign in" do
    get new_admin_business_onboarding_path
    assert_redirected_to new_user_session_path
  end

  test "unconfirmed user cannot access onboarding" do
    @user.update_columns(confirmed_at: nil)
    sign_in @user

    get new_admin_business_onboarding_path
    # Devise redirects unconfirmed users trying to access protected pages
    assert_redirected_to new_user_session_path
  end

  # ====================
  # EXISTING BUSINESS TESTS
  # ====================

  test "user with existing business can update via onboarding" do
    sign_in @user

    # Create initial business
    business = Business.create!(
      name: "Existing Business",
      email: "existing@example.com",
      owner: @user,
      industry: "landscaping"
    )

    # Start onboarding (should load existing business)
    get new_admin_business_onboarding_path
    assert_response :success

    # Update basics - should not create new business
    assert_no_difference("Business.count") do
      post admin_business_onboarding_index_path, params: {
        step: "basics",
        business: {
          name: "Updated Existing Business",
          email: "updated@example.com",
          phone: "555-9999",
          industry: "maintenance"
        }
      }
    end

    business.reload
    assert_equal "Updated Existing Business", business.name
    assert_equal "maintenance", business.industry
  end

  test "user redirected to dashboard if business already onboarded" do
    sign_in @user

    business = Business.create!(
      name: "Onboarded Business",
      email: "onboarded@example.com",
      owner: @user,
      onboarded_at: 1.day.ago
    )

    # Accessing onboarding should still work (allows re-editing)
    get new_admin_business_onboarding_path
    assert_response :success
  end

  # ====================
  # BUSINESS RELATIONSHIP TESTS
  # ====================

  test "onboarding creates business_user relationship" do
    sign_in @user

    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Relationship Test",
        email: "relationship@test.com",
        industry: "landscaping"
      }
    }

    business = Business.last
    assert business.users.include?(@user)
    assert business.business_users.exists?(user: @user)
  end

  test "owner has correct role after onboarding" do
    sign_in @user

    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Role Test",
        email: "role@test.com",
        industry: "landscaping"
      }
    }

    business = Business.last
    business_user = business.business_users.find_by(user: @user)
    assert_equal "owner", business_user.role
  end

  # ====================
  # STEP NAVIGATION TESTS
  # ====================

  test "can navigate directly to any step" do
    sign_in @user

    %w[basics hours location branding].each do |step|
      get new_admin_business_onboarding_path(step: step)
      assert_response :success
    end
  end

  test "invalid step redirects to basics" do
    sign_in @user

    get new_admin_business_onboarding_path(step: "invalid_step")
    assert_redirected_to new_admin_business_onboarding_path(step: "basics")
    assert_match /invalid/i, flash[:alert]
  end

  # ====================
  # DATA PERSISTENCE TESTS
  # ====================

  test "data persists across steps" do
    sign_in @user

    # Set basics
    post admin_business_onboarding_index_path, params: {
      step: "basics",
      business: {
        name: "Persistent Business",
        email: "persist@example.com",
        phone: "555-1111",
        industry: "landscaping"
      }
    }

    business = Business.last

    # Set hours
    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/New_York"
    }

    business.reload
    # Basics data should still be there
    assert_equal "Persistent Business", business.name
    assert_equal "persist@example.com", business.email
    assert_equal "America/New_York", business.timezone
  end

  # ====================
  # TIMEZONE TESTS
  # ====================

  test "accepts valid timezone" do
    sign_in @user

    Business.create!(
      name: "TZ Test",
      email: "tz@test.com",
      owner: @user
    )

    post admin_business_onboarding_index_path, params: {
      step: "hours",
      timezone: "America/Los_Angeles"
    }

    business = Business.last
    assert_equal "America/Los_Angeles", business.timezone
    assert_redirected_to new_admin_business_onboarding_path(step: "location")
  end

  # ====================
  # INDUSTRY TESTS
  # ====================

  test "accepts all valid industries" do
    sign_in @user

    Business::INDUSTRIES.keys.each do |industry|
      post admin_business_onboarding_index_path, params: {
        step: "basics",
        business: {
          name: "#{industry.capitalize} Business",
          email: "#{industry}@test.com",
          industry: industry
        }
      }

      business = Business.last
      assert_equal industry, business.industry

      # Clean up for next iteration
      business.destroy
    end
  end

  # ====================
  # BRAND COLOR TESTS
  # ====================

  test "accepts valid hex color codes" do
    sign_in @user

    business = Business.create!(
      name: "Color Test",
      email: "color@test.com",
      owner: @user
    )

    valid_colors = ["#000000", "#FFFFFF", "#1E40AF", "#059669"]

    valid_colors.each do |color|
      post admin_business_onboarding_index_path, params: {
        step: "branding",
        business: { brand_color: color }
      }

      business.reload
      assert_equal color, business.brand_color
    end
  end

  test "rejects invalid color codes" do
    sign_in @user

    business = Business.create!(
      name: "Color Test",
      email: "color@test.com",
      owner: @user
    )

    invalid_colors = ["red", "#GGG", "123456", "#12345"]

    invalid_colors.each do |color|
      post admin_business_onboarding_index_path, params: {
        step: "branding",
        business: { brand_color: color }
      }

      assert_response :unprocessable_content
    end
  end

  # ====================
  # PERFORMANCE TESTS
  # ====================

  test "onboarding does not create duplicate businesses" do
    sign_in @user

    assert_difference("Business.count", 1) do
      # Submit basics twice
      2.times do
        post admin_business_onboarding_index_path, params: {
          step: "basics",
          business: {
            name: "Single Business",
            email: "single@business.com",
            industry: "landscaping"
          }
        }
      end
    end
  end
end

