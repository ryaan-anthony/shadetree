require "test_helper"

# OPS-03: viewing the app as a member: a reason to start, read-only by default, a second reason
# to allow changes, sensitive areas always blocked, timeouts, the banner and the audit trail.
class Ops::ImpersonationTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:two)
    @owner = business_users(:two) # users(:two), the Owner of business two
  end

  def start(member = @owner, reason: "Ticket: can't find the invoice button")
    post ops_business_impersonation_path(@business), params: { member: member.uid, reason: }
  end

  def later(duration) = travel_to(Time.current + duration) # travel is from the real now; this adds up

  def allow_changes = patch(ops_impersonation_path, params: { mode: "write", reason: "Fixing their tax rate with them" })

  test "starting needs a reason and an allowed member; the session is that member, read-only, with a banner" do
    sign_in_operator
    start(reason: "")
    assert_match "Give a reason", flash[:alert]
    start(business_users(:one_member_of_two))
    assert_match "yourself", flash[:alert]
    Operator.grant!(users(:two))
    start
    assert_match "Operators can't", flash[:alert]
    Operator.for(users(:two)).update_columns(revoked_at: Time.current)

    start
    assert_redirected_to admin_root_path
    entry = AuditEntry.find_by!(action: "impersonation.started")
    assert_equal [ @business, users(:two), "Ticket: can't find the invoice button", "read_only" ], [ entry.business, entry.target_user, entry.reason, entry.data["mode"] ]
    follow_redirect!
    assert_response :success
    assert_select "#impersonation-banner", /Viewing as Jane Smith.*Owner.*Test Business Two/m
    assert_select "#impersonation-mode", "Read-only"
    assert_select "#impersonation-banner", /user1@example.com/
    get ops_business_path(@business)
    assert_select "#impersonation-banner"
    assert_select "#view-as", /Stop that first/

    start
    assert_match "already viewing", flash[:alert], "no nesting"
    assert_equal 1, AuditEntry.where(action: "impersonation.started").count
  end

  test "read-only blocks every change and the GETs that write; browsing leaves no trace on the member" do
    sign_in_operator
    notification = as_business(@business) { Notification.create!(user: users(:two), kind: "new_request", title: "New request", path: "/admin") }
    start
    assert_no_difference -> { as_business(@business) { Client.count } } do
      post admin_clients_path, params: { client: { display_name: "Nope" } }
    end
    assert_redirected_to admin_root_path
    assert_match "read-only", flash[:alert]
    get open_admin_notification_path(notification)
    assert_nil notification.reload.read_at
    assert_nil @owner.reload.last_active_at
    get download_admin_data_exports_path(table: "clients")
    assert_match "read-only", flash[:alert]
    patch user_registration_path, params: { user: { first_name: "Hacked" } }
    assert_equal "Jane", users(:two).reload.first_name
    assert_not AuditEntry.exists?(action: "impersonation.change")
  end

  test "allowing changes needs a second reason; changes are audited; sensitive areas stay blocked" do
    sign_in_operator
    start
    patch ops_impersonation_path, params: { mode: "write", reason: "" }
    assert_response :unprocessable_content
    allow_changes
    assert_equal "Fixing their tax rate with them", AuditEntry.find_by!(action: "impersonation.changes_allowed").reason
    follow_redirect!
    assert_select "#impersonation-mode", "Changes allowed"

    post admin_clients_path, params: { client: { display_name: "Added by support", contact_methods_attributes: { "0" => { kind: "phone", value: "5550100100" } } } }
    assert as_business(@business) { Client.exists?(display_name: "Added by support") }
    change = AuditEntry.find_by!(action: "impersonation.change")
    assert_equal [ users(:two), "admin/clients#create", "POST" ], [ change.target_user, change.data["change"], change.data["method"] ]

    blocked = {
      -> { patch user_registration_path, params: { user: { email: "x@example.com", current_password: "password123" } } } => "account settings",
      -> { delete destroy_user_session_path } => "account settings",
      -> { post switch_admin_business_path, params: { business: businesses(:one).uid } } => "which business",
      -> { patch admin_member_path(@owner), params: { member: { role: "admin" } } } => "Owners' roles",
      -> { patch admin_member_path(business_users(:one_member_of_two)), params: { member: { role: "owner" } } } => "Owners' roles"
    }
    blocked.each do |request, words|
      request.call
      assert_match words, flash[:alert]
    end
    assert_equal "user2@example.com", users(:two).reload.email
    assert_equal "technician", business_users(:one_member_of_two).reload.role
    assert_equal 1, AuditEntry.where(action: "impersonation.change").count

    patch ops_impersonation_path, params: { mode: "read_only" }
    assert AuditEntry.exists?(action: "impersonation.read_only")
    post admin_clients_path, params: { client: { display_name: "Again" } }
    assert_match "read-only", flash[:alert]
  end

  test "stopping restores the operator; sessions time out when idle and after an hour" do
    sign_in_operator
    start
    later 4.minutes
    delete ops_impersonation_path
    assert_redirected_to ops_business_path(@business)
    ended = AuditEntry.find_by!(action: "impersonation.ended")
    assert_equal [ "stopped", 4 ], ended.data.values_at("ended", "minutes")
    get admin_root_path
    assert_select "#impersonation-banner", 0
    assert_equal users(:one), controller.send(:current_user)

    start
    later 16.minutes
    get admin_root_path
    assert_redirected_to ops_business_path(@business)
    assert_equal "timed_out", AuditEntry.where(action: "impersonation.ended").last.data["ended"]
    get admin_root_path
    assert_select "#impersonation-banner", 0

    get ops_root_path # the console's own idle limit passed too
    post ops_two_factor_verification_path, params: { code: Totp.code(Operator.for(users(:one)).otp_secret, Time.current.to_i / Totp::STEP) }
    start
    5.times do
      later 10.minutes
      get admin_root_path
      assert_response :success
    end
    later 11.minutes
    get admin_root_path
    assert_redirected_to ops_business_path(@business), "ends after an hour, however active"
  end

  test "a membership ending ends the session; non-operators can't start one" do
    sign_in_operator
    start
    @owner.update_columns(role: "owner", active: false)
    get admin_root_path
    assert_redirected_to ops_business_path(@business)
    assert_equal "access_changed", AuditEntry.where(action: "impersonation.ended").last.data["ended"]

    sign_out :user
    sign_in users(:two)
    post ops_business_impersonation_path(businesses(:one)), params: { member: business_users(:one).uid, reason: "x" }
    assert_response :not_found
  end

  test "Owners see that support viewed their account; Admins don't" do
    sign_in_operator
    start
    allow_changes
    post admin_clients_path, params: { client: { display_name: "Added by support", contact_methods_attributes: { "0" => { kind: "phone", value: "5550100100" } } } }
    later 3.minutes
    delete ops_impersonation_path
    sign_out :user

    sign_in users(:two)
    get admin_team_path
    assert_select "#support-access li", 1
    assert_select "#support-access", /Viewed as Jane Smith for 3 minutes · changes allowed \(1 change\)/
    assert_no_match "user1@example.com", css_select("#support-access").text
    business_users(:one_member_of_two).update_columns(role: "admin")
    sign_out :user
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_team_path
    assert_select "#support-access", 0
  end
end
