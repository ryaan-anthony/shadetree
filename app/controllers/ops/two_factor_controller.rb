# OPS-01: setting up two-factor (an authenticator app, with recovery codes) and verifying it to
# enter the console.
class Ops::TwoFactorController < Ops::BaseController
  skip_before_action :require_two_factor

  # Setup: a new secret as a QR code, confirmed with a first code.
  def setup
    return redirect_to(ops_root_path) if current_operator.two_factor?

    current_operator.start_enrollment! unless current_operator.otp_secret
    @secret = current_operator.otp_secret
    @qr = RQRCode::QRCode.new(Totp.uri(@secret, account: current_user.email)).as_svg(module_size: 4, use_path: true, viewbox: true)
  end

  def enable
    return redirect_to(ops_root_path) if current_operator.two_factor?

    @recovery_codes = current_operator.enable_two_factor!(params[:code])
    if @recovery_codes
      mark_verified
      audit!("operator.two_factor_enabled")
      render :recovery_codes
    else
      redirect_to ops_two_factor_setup_path, alert: "That code didn't match. Check your phone's clock and try the newest code."
    end
  end

  def new
    redirect_to(ops_two_factor_setup_path) unless current_operator.two_factor?
  end

  def create
    return redirect_to(ops_two_factor_setup_path) unless current_operator.two_factor?

    if current_operator.verify_two_factor(params[:code])
      first = ops_session["ops_verified_at"].nil?
      mark_verified
      audit!("console.signed_in") if first
      redirect_to ops_session.delete("ops_return_to").presence || ops_root_path
    else
      flash.now[:alert] = "That code didn't work. Codes change every 30 seconds, and each works once."
      render :new, status: :unprocessable_content
    end
  end

  private

  def mark_verified
    ops_session["ops_verified_at"] = Time.current.to_i
    ops_session["ops_seen_at"] = Time.current.to_i
  end
end
