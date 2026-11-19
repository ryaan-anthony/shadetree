require "test_helper"

# OPS-01: the operator console: hidden from everyone else, two-factor to enter, idle expiry,
# fresh codes for access changes, and the append-only audit log.
class Ops::OperatorConsoleTest < ActionDispatch::IntegrationTest
  setup do
    @founder = users(:one)
    @operator = Operator.grant!(@founder)
  end

  def code_for(operator, at: Time.current) = Totp.code(operator.reload.otp_secret, at.to_i / Totp::STEP)

  def enroll
    sign_in @founder
    get ops_root_path
    follow_redirect! # setup
    post ops_two_factor_setup_path, params: { code: code_for(@operator), password: "password123" }
  end

  test "non-operators, signed in or not, get not found" do
    get ops_root_path
    assert_response :not_found
    sign_in users(:two)
    get ops_root_path
    assert_response :not_found
    get ops_audit_entries_path
    assert_response :not_found
    @operator.update_columns(revoked_at: Time.current)
    sign_in @founder
    get ops_root_path
    assert_response :not_found
  end

  test "an operator sets up two-factor, saves recovery codes, then enters with a code every session" do
    sign_in @founder
    get ops_root_path
    assert_redirected_to ops_two_factor_setup_path
    follow_redirect!
    assert_select "#otp-secret"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    post ops_two_factor_setup_path, params: { code: "000000", password: "password123" }
    assert_redirected_to ops_two_factor_setup_path
    post ops_two_factor_setup_path, params: { code: code_for(@operator), password: "wrong" }
    assert_match "password didn't match", flash[:alert]
    assert_not @operator.reload.two_factor?
    assert_enqueued_email_with OperatorMailer, :two_factor_enabled, params: { user: @founder } do
      post ops_two_factor_setup_path, params: { code: code_for(@operator), password: "password123" }
    end
    assert_select "#recovery-codes li", Operator::RECOVERY_CODES
    recovery = css_select("#recovery-codes li").first.text
    assert @operator.reload.two_factor?
    get ops_root_path
    assert_response :success

    sign_out :user
    sign_in @founder
    get ops_audit_entries_path
    assert_redirected_to new_ops_two_factor_verification_path
    post ops_two_factor_verification_path, params: { code: "123456" }
    assert_response :unprocessable_content
    post ops_two_factor_verification_path, params: { code: recovery.delete("-").upcase }
    assert_redirected_to ops_audit_entries_path, "typed without the dash, in any case"
    assert_equal({ "left" => Operator::RECOVERY_CODES - 1 }, AuditEntry.find_by(action: "operator.recovery_code_used").data)

    sign_out :user
    sign_in @founder
    get ops_root_path
    post ops_two_factor_verification_path, params: { code: recovery }
    assert_response :unprocessable_content, "a recovery code works once"
  end

  test "an idle session must verify again; access changes need a fresh code" do
    enroll
    travel 16.minutes do
      get ops_operators_path
      assert_redirected_to new_ops_two_factor_verification_path
      post ops_two_factor_verification_path, params: { code: code_for(@operator) }
      assert_redirected_to ops_operators_path
    end
    travel 22.minutes do
      get ops_operators_path # still active, but the code is old
      post ops_operators_path, params: { email: users(:two).email }
      assert_redirected_to new_ops_two_factor_verification_path(recent: 1)
      assert_nil Operator.for(users(:two))
      post ops_two_factor_verification_path, params: { code: code_for(@operator) }
      post ops_operators_path, params: { email: users(:two).email }
      assert Operator.for(users(:two))
    end
  end

  test "operators grant and revoke others, never the last one; every change is in the audit log, which can't be changed" do
    enroll
    post ops_operators_path, params: { email: "nobody@example.com" }
    assert_match "no Shadetree account", flash[:alert]
    assert_enqueued_email_with OperatorMailer, :granted, params: { user: users(:two) } do
      post ops_operators_path, params: { email: users(:two).email.upcase }
    end
    second = Operator.for(users(:two))
    assert second
    delete ops_operator_path(second)
    assert_nil Operator.for(users(:two))
    delete ops_operator_path(@operator)
    assert_match "last operator", flash[:alert]
    assert Operator.for(@founder)

    get ops_audit_entries_path(action_name: "operator.granted")
    assert_select "#audit-entries li", 1
    assert_select "#audit-entries li", /Granted operator access.*#{users(:two).email}.*#{@founder.email}/m
    get ops_audit_entries_path(operator: @founder.email)
    assert_select "#audit-entries li", AuditEntry.where(operator_email: @founder.email).count

    entry = AuditEntry.last
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(reason: "edited") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
    assert AuditEntry.append_only?
    refused = ->(&sql) { assert_raises(ActiveRecord::StatementInvalid) { AuditEntry.transaction(requires_new: true, &sql) } }
    refused.call { AuditEntry.where(id: entry.id).update_all(reason: "edited") }
    refused.call { AuditEntry.where(id: entry.id).delete_all }
    refused.call { AuditEntry.connection.execute("TRUNCATE audit_entries") }
  end

  test "wrong codes in a row lock code checks for an hour, recorded once" do
    enroll
    sign_out :user
    sign_in @founder
    Operator::MAX_FAILED_ATTEMPTS.times do |i|
      travel_to(Time.current + (i * 15).seconds) { post ops_two_factor_verification_path, params: { code: "000000" } }
    end
    assert @operator.reload.locked?
    assert_match "Too many wrong codes", flash[:alert]
    travel 1.minute do
      post ops_two_factor_verification_path, params: { code: code_for(@operator) }
      assert_response :unprocessable_content, "the right code isn't checked while locked"
    end
    assert_equal 1, AuditEntry.where(action: "operator.locked_out").count
    travel 63.minutes do
      post ops_two_factor_verification_path, params: { code: code_for(@operator) }
      assert_redirected_to ops_root_path
      assert_equal 0, @operator.reload.failed_attempts
    end
  end

  test "an unconfirmed setup key is replaced after a while" do
    sign_in @founder
    get ops_two_factor_setup_path
    first = @operator.reload.otp_secret
    get ops_two_factor_setup_path
    assert_equal first, @operator.reload.otp_secret, "the same key while setting up"
    travel 16.minutes do
      code = code_for(@operator)
      post ops_two_factor_setup_path, params: { code:, password: "password123" }
      assert_not @operator.reload.two_factor?, "a stale key can't be confirmed"
      get ops_two_factor_setup_path
      assert_not_equal first, @operator.reload.otp_secret
    end
  end

  test "a verified session is tied to the grant and the two-factor setup" do
    enroll
    get ops_root_path
    assert_response :success
    @operator.reset_two_factor!
    @operator.update!(otp_secret: Totp.random_secret, otp_started_at: Time.current, otp_enabled_at: 1.minute.from_now)
    get ops_root_path
    assert_redirected_to new_ops_two_factor_verification_path, "a new setup elsewhere means a new code here"
  end

  test "after a code, only console pages are returned to" do
    enroll
    travel 6.minutes do
      post ops_operators_path, params: { email: users(:two).email }, headers: { "Referer" => "https://evil.example/elsewhere" }
      post ops_two_factor_verification_path, params: { code: code_for(@operator) }
      assert_redirected_to ops_root_path
    end
  end

  test "recovery codes can be replaced; the log's filters don't widen on a typo" do
    enroll
    old = AuditEntry.find_by(action: "operator.two_factor_enabled")
    get ops_root_path
    assert_select "#recovery-codes-left", /10 recovery codes/
    post ops_two_factor_recovery_codes_path
    assert_select "#recovery-codes li", Operator::RECOVERY_CODES
    assert AuditEntry.exists?(action: "operator.recovery_codes_regenerated")
    AuditEntry.record!(operator: @founder, action: "operator.granted", business: businesses(:one))
    get ops_audit_entries_path(business: "nope")
    assert_select "#audit-entries", 0
    get ops_audit_entries_path(business: businesses(:one).uid)
    assert_select "#audit-entries li", 1
    get ops_audit_entries_path(page: 10**30)
    assert_response :success
    assert old
  end

  test "users and businesses named in the log can still be deleted" do
    user = User.create!(email: "temp@example.com", password: "password123", first_name: "Temp", last_name: "User", confirmed_at: Time.current)
    entry = AuditEntry.record!(operator: @founder, action: "operator.granted", user:)
    user.destroy!
    assert_equal user.id, entry.reload.target_user_id
    assert_nil entry.target_user
  end

  test "non-operators get not found even for a forged post" do
    ActionController::Base.allow_forgery_protection = true
    sign_in users(:two)
    post ops_operators_path, params: { email: "x@example.com" }
    assert_response :not_found
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
