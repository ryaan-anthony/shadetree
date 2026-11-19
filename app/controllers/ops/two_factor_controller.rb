# OPS-01: setting up two-factor (an authenticator app, with recovery codes) and verifying it to
# enter the console. Codes are rate limited per user, and MAX_FAILED_ATTEMPTS wrong ones in a
# row lock code checks for a while (Operator), which is audited.
class Ops::TwoFactorController < Ops::BaseController
  skip_before_action :require_two_factor, except: :regenerate
  before_action :require_recent_verification, only: :regenerate

  too_many = -> { redirect_to(request.path == ops_two_factor_setup_path ? ops_two_factor_setup_path : new_ops_two_factor_verification_path, alert: "Too many tries. Wait a minute and try again.") }
  rate_limit to: 5, within: 1.minute, by: -> { current_user.id }, only: %i[create enable], with: too_many
  rate_limit to: 20, within: 1.hour, by: -> { current_user.id }, only: %i[create enable], with: too_many, name: "hourly"

  # Setup: a secret as a QR code, confirmed with a first code and the account password.
  def setup
    return redirect_to(ops_root_path) if current_operator.two_factor?

    @secret = current_operator.enrollment_secret!
    @qr = RQRCode::QRCode.new(Totp.uri(@secret, account: current_user.email)).as_svg(module_size: 4, use_path: true, viewbox: true)
  end

  def enable
    return redirect_to(ops_root_path) if current_operator.two_factor?
    return redirect_to(ops_two_factor_setup_path, alert: locked_message) if current_operator.locked?
    return redirect_to(ops_two_factor_setup_path, alert: "That password didn't match your account.") unless current_user.valid_password?(params[:password].to_s)

    @recovery_codes = current_operator.enable_two_factor!(params[:code])
    if @recovery_codes
      mark_verified
      audit!("operator.two_factor_enabled")
      OperatorMailer.with(user: current_user).two_factor_enabled.deliver_later
      render :recovery_codes
    else
      audit_lockout
      redirect_to ops_two_factor_setup_path, alert: current_operator.locked? ? locked_message : "That code didn't match. Check your phone's clock and try the newest code."
    end
  end

  def new
    redirect_to(ops_two_factor_setup_path) unless current_operator.two_factor?
  end

  def create
    return redirect_to(ops_two_factor_setup_path) unless current_operator.two_factor?

    if (kind = current_operator.verify_two_factor(params[:code]))
      first = ops_session["ops_verified_at"].nil?
      mark_verified
      audit!("console.signed_in") if first
      audit!("operator.recovery_code_used", left: current_operator.recovery_codes_left) if kind == :recovery
      flash[:alert] = "You have #{helpers.pluralize(current_operator.recovery_codes_left, "recovery code")} left. Make new ones from the console's home." if kind == :recovery && current_operator.recovery_codes_left <= 3
      redirect_to url_from(console_path(ops_session.delete("ops_return_to"))) || ops_root_path
    else
      audit_lockout
      flash.now[:alert] = current_operator.locked? ? locked_message : "That code didn't work. Codes change every 30 seconds, and each works once."
      render :new, status: :unprocessable_content
    end
  end

  # A fresh set of recovery codes (the old ones stop working).
  def regenerate
    @recovery_codes = current_operator.regenerate_recovery_codes!
    audit!("operator.recovery_codes_regenerated")
    render :recovery_codes
  end

  private

  def locked_message
    "Too many wrong codes. Codes aren't checked until #{current_operator.locked_until.utc.strftime("%H:%M UTC")}. If you've lost your phone and recovery codes, ask another operator."
  end

  # Recorded once, when a wrong code starts the lock.
  def audit_lockout
    return unless current_operator.locked? && current_operator.saved_change_to_locked_until?

    audit!("operator.locked_out", attempts: Operator::MAX_FAILED_ATTEMPTS)
  end
end
