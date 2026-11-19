require "test_helper"

class Users::SignUpTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def sign_up(**overrides)
    post user_registration_path, params: { user: {
      first_name: "Ana", last_name: "Silva", email: "ana@example.com",
      password: "long enough phrase", terms_of_service: "1"
    }.merge(overrides), **form_guard_params("sign-up") }
  end

  test "the form asks for name, email, password and terms only" do
    get new_user_registration_path
    assert_response :success
    assert_select "form input:not([type=hidden]):not([type=submit]):not([name=website])", 5 # first, last, email, password, terms
    assert_select "input#user_password[minlength='10'][autocomplete='new-password']"
    assert_select "[data-controller='password-strength']"
    assert_select "a[href='#{terms_path}']"
    assert_select "input[name='user[password_confirmation]']", count: 0
  end

  test "signing up signs you in, sends a confirmation and lands in business setup" do
    assert_emails(1) { sign_up }
    user = User.find_by!(email: "ana@example.com")
    assert_redirected_to new_admin_business_path
    assert_equal [ "Ana", "Silva" ], [ user.first_name, user.last_name ]
    assert_not user.confirmed?
    assert_not_nil user.terms_accepted_at

    follow_redirect!
    assert_response :success
    assert_select "#confirm-email-banner", /Confirm your email/
  end

  test "terms must be accepted" do
    assert_no_difference("User.count") { sign_up(terms_of_service: "0") }
    assert_response :unprocessable_entity
    assert_select ".error-text", /must be accepted/
  end

  test "terms can't be skipped by leaving the field out" do
    assert_no_difference("User.count") do
      post user_registration_path, params: { user: { first_name: "Ana", email: "ana@example.com", password: "long enough phrase" }, **form_guard_params("sign-up") }
    end
    assert_response :unprocessable_entity
  end

  test "Devise emails use the branded layout, sent in the background" do
    assert_enqueued_with(job: PlatformMailDeliveryJob) { sign_up }
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_match "Confirm your email", mail.body.to_s
    assert_match "activity on your Shadetree account", mail.body.to_s
  end

  test "name is required and passwords need 10 characters" do
    assert_no_difference("User.count") { sign_up(first_name: "", password: "short") }
    assert_select "#user_first_name[aria-invalid='true']"
    assert_select "#user_password[aria-invalid='true']"
  end

  test "duplicate emails are rejected" do
    assert_no_difference("User.count") { sign_up(email: users(:one).email) }
    assert_response :unprocessable_entity
  end

  test "bots are turned away: the hidden field, a form sent too fast or from elsewhere, and too many tries" do
    assert_no_difference("User.count") do
      post user_registration_path, params: { user: { first_name: "Bot", email: "bot@example.com", password: "long enough phrase", terms_of_service: "1" },
                                             **form_guard_params("sign-up"), website: "http://spam.example" }
    end
    assert_redirected_to root_path

    assert_no_difference("User.count") do
      post user_registration_path, params: { user: { first_name: "Ana", email: "ana@example.com", password: "long enough phrase", terms_of_service: "1" },
                                             **form_guard_params("sign-up", at: 1.second.ago) }
    end
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Check your details/
    assert_select "input[name='user[email]'][value='ana@example.com']"
    assert_select "input[name='user[password]']:not([value])"

    post user_registration_path, params: { user: { first_name: "Ana", email: "ana@example.com" }, **form_guard_params("request:oakline") }
    assert_response :unprocessable_content, "a token from another form doesn't count"

    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    10.times { post user_registration_path, params: { user: { first_name: "" }, **form_guard_params("sign-up") } }
    assert_no_difference("User.count") { sign_up }
    assert_select "[role=alert]", /a lot of sign-ups/
  ensure
    Rails.cache = cache if cache
  end

  test "in a lockdown, forms wait longer and allow fewer tries" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    AbuseProtection.lockdown!(hours: 1)
    post user_registration_path, params: { user: { first_name: "Ana" }, **form_guard_params("sign-up", at: 5.seconds.ago) }
    assert_select "[role=alert]", /Check your details/
    2.times { post user_registration_path, params: { user: { first_name: "" }, **form_guard_params("sign-up", at: 20.seconds.ago) } }
    assert_no_difference("User.count") { post user_registration_path, params: { user: { first_name: "Ana", last_name: "Silva", email: "ana@example.com", password: "long enough phrase", terms_of_service: "1" }, **form_guard_params("sign-up", at: 20.seconds.ago) } }
    assert_select "[role=alert]", /a lot of sign-ups/
    AbuseProtection.lift_lockdown!
    Rails.cache.clear
    assert_difference("User.count") { sign_up }
  ensure
    Rails.cache = cache
  end
end
