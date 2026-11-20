# Signing in to the operator console in integration tests (OPS-01): grants access, sets up
# two-factor (or, when it's set up already, enters the next unused code) and verifies this session.
module OperatorHelpers
  def sign_in_operator(user = users(:one))
    operator = Operator.grant!(user).reload
    sign_in user
    now = Time.current.to_i / Totp::STEP
    if operator.two_factor?
      get new_ops_two_factor_verification_path
      step = operator.otp_last_step.to_i >= now ? now + 1 : now # each code works once; the next one is accepted early
      post ops_two_factor_verification_path, params: { code: Totp.code(operator.otp_secret, step) }
    else
      get ops_two_factor_setup_path
      post ops_two_factor_setup_path, params: { code: Totp.code(operator.reload.otp_secret, now), password: "password123" }
    end
    assert operator.reload.two_factor?, "operator two-factor setup failed"
    operator
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) { include OperatorHelpers }
