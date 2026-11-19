# Signing in to the operator console in integration tests (OPS-01): grants access, sets up
# two-factor and verifies this session.
module OperatorHelpers
  def sign_in_operator(user = users(:one))
    operator = Operator.grant!(user)
    sign_in user
    get ops_two_factor_setup_path
    post ops_two_factor_setup_path, params: { code: Totp.code(operator.reload.otp_secret, Time.current.to_i / Totp::STEP), password: "password123" }
    assert operator.reload.two_factor?, "operator two-factor setup failed"
    operator
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) { include OperatorHelpers }
