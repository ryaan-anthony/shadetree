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
    post ops_two_factor_setup_path, params: { code: code_for(@operator) }
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
    post ops_two_factor_setup_path, params: { code: "000000" }
    assert_redirected_to ops_two_factor_setup_path
    post ops_two_factor_setup_path, params: { code: code_for(@operator) }
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
    post ops_two_factor_verification_path, params: { code: recovery }
    assert_redirected_to ops_audit_entries_path

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
    post ops_operators_path, params: { email: users(:two).email.upcase }
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
    assert_raises(ActiveRecord::StatementInvalid) { AuditEntry.where(id: entry.id).update_all(reason: "edited") }
    assert_raises(ActiveRecord::StatementInvalid) { AuditEntry.where(id: entry.id).delete_all }
  end
end
