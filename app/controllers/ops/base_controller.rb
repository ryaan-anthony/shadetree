# The operator console (OPS-01, ADR 0019): its own area and layout, for operators only. Anyone
# else, signed in or not, gets "not found". Inside, an operator must have set up two-factor and
# verified this session; the session ends after IDLE_TIMEOUT without a request, and sensitive
# actions need a fresh code (require_recent_verification).
class Ops::BaseController < ApplicationController
  IDLE_TIMEOUT = 15.minutes
  RECENT = 5.minutes

  layout "ops"

  # Before forgery protection too, so a non-operator's POST is "not found" like everything else.
  prepend_before_action :require_operator
  prepend_before_action :set_console_headers
  before_action :expire_idle_session
  before_action :require_two_factor

  helper_method :current_operator, :ops_session

  private

  def current_operator = @current_operator

  # Console state lives in the signed-in user's own session data, which signing out clears.
  def ops_session = warden.session(:user)

  def set_console_headers
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    response.set_header("Cache-Control", "no-store")
  end

  def require_operator
    @current_operator = Operator.for(current_user) if user_signed_in?
    raise ActionController::RoutingError, "Not Found" unless @current_operator
  end

  def expire_idle_session
    last = ops_session["ops_seen_at"]
    if last && Time.zone.at(last) < IDLE_TIMEOUT.ago
      ops_session.delete("ops_verified_at")
      ops_session.delete("ops_seen_at")
      flash[:alert] = "Your console session ended after #{IDLE_TIMEOUT.in_minutes.to_i} minutes idle. Enter a code to go on."
    end
    ops_session["ops_seen_at"] = Time.current.to_i
  end

  def require_two_factor
    return redirect_to(ops_two_factor_setup_path) unless current_operator.two_factor?
    return if verified?

    ops_session["ops_return_to"] = request.fullpath if request.get? || request.head?
    redirect_to new_ops_two_factor_verification_path
  end

  # Verification counts for this grant and this two-factor setup only: after a revoke and
  # re-grant, or a reset, an old browser session has to enter a code again.
  def verification_key = [ current_operator.id, current_operator.otp_enabled_at.to_i ]

  def verified?
    return false unless ops_session["ops_verified_at"]
    return true if ops_session["ops_verified_for"] == verification_key

    ops_session.delete("ops_verified_at")
    false
  end

  def mark_verified
    ops_session["ops_verified_at"] = Time.current.to_i
    ops_session["ops_verified_for"] = verification_key
    ops_session["ops_seen_at"] = Time.current.to_i
  end

  def verified_recently? = verified? && Time.zone.at(ops_session["ops_verified_at"]) > RECENT.ago

  # Where to go after a code: a console page, never another host.
  def console_path(url)
    path = URI.parse(url.to_s).path.to_s
    path.start_with?("/ops") ? path : nil
  rescue URI::InvalidURIError
    nil
  end

  # For actions that change access or data: a code entered in the last few minutes.
  def require_recent_verification
    return if verified_recently?

    ops_session["ops_return_to"] = console_path(request.referer) || ops_root_path
    redirect_to new_ops_two_factor_verification_path(recent: 1), alert: "Enter a code to confirm it's you."
  end

  def audit!(action, **)
    AuditEntry.record!(operator: current_user, action:, request:, **)
  end
end
