# OPS-03: while an operator views the app as a member (Impersonation), current_user is that
# member everywhere but the console, and this guard decides what may happen:
#
# - Read-only (the default): nothing that changes anything. Every request but GET/HEAD is
#   refused, and so are the few GETs that write (a data download is logged in the member's name).
# - Changes allowed: still never account settings (password, email, sign-in, deleting the
#   account), billing and plans, payment accounts, Owner roles, or adding or switching
#   businesses. Every change that goes through is in the audit log.
#
# The console (Ops::) always acts as the operator. Ending the session is Ops::ImpersonationsController#destroy.
module ImpersonationSupport
  extend ActiveSupport::Concern

  READ_ONLY_GETS = { "admin/data_exports" => %w[download] }.freeze

  included do
    helper_method :impersonation, :true_user
    before_action :guard_impersonation
    after_action :audit_impersonated_change
  end

  # The member being viewed as, or the signed-in user.
  def current_user
    impersonation&.user || super
  end

  private

  # Whoever actually signed in.
  def true_user = warden.user(:user)

  def impersonation
    return @impersonation if defined?(@impersonation)

    # Renders outside a request (ApplicationController.render) have no Warden, and no impersonation.
    @impersonation = (Impersonation.load(warden.session(:user), true_user) if request.env["warden"] && warden.authenticated?(:user))
    @impersonation = nil if @impersonation&.ended_because
    @impersonation
  end

  def guard_impersonation
    return unless warden.authenticated?(:user) && Impersonation.present?(warden.session(:user))

    stale = Impersonation.load(warden.session(:user), true_user)
    if (because = stale.ended_because)
      end_impersonation!(stale, because)
      return if is_a?(Ops::BaseController)

      return redirect_to(stale.membership ? ops_business_path(stale.membership.business) : ops_root_path,
                         alert: "Your view as a member ended (#{because == "timed_out" ? "it timed out" : "access changed"}).")
    end
    return if is_a?(Ops::BaseController)

    impersonation.touch!
    warden.session(:user)["ops_seen_at"] = Time.current.to_i # viewing as a member is console activity
    refusal = impersonation_refusal
    refuse_while_impersonating(refusal) if refusal
  end

  def impersonation_refusal
    reading = request.get? || request.head?
    return if reading && !READ_ONLY_GETS.fetch(controller_path, []).include?(action_name)
    return "You're viewing in read-only mode, so nothing was changed." if impersonation.read_only?

    blocked = impersonation_blocked_area
    "Support can't change #{blocked}, even with changes allowed." if blocked
  end

  def impersonation_blocked_area
    path = controller_path
    if path.start_with?("users/") then "account settings or sign-in"
    elsif path.match?(/plan|billing|subscription/) then "billing or plans"
    elsif path.match?(/payment_account|payments_account|connect/) then "the payment account"
    elsif path == "admin/businesses" && %w[new create switch].include?(action_name) then "which business is in use"
    elsif path == "admin/members" && owner_role_change? then "Owners' roles"
    elsif path.start_with?("client") then "anything as a client"
    end
  end

  def owner_role_change?
    target = impersonation.business.business_users.find_by(uid: params[:id].to_s)
    target.nil? || target.owner? || params.dig(:member, :role).to_s == "owner"
  end

  def refuse_while_impersonating(message)
    return head(:forbidden) unless request.format.html? || request.format.turbo_stream?

    redirect_back_or_to admin_root_path, alert: message, status: :see_other
  end

  def audit_impersonated_change
    return if is_a?(Ops::BaseController) || impersonation.nil? || request.get? || request.head?

    AuditEntry.record!(operator: true_user, action: "impersonation.change", business: impersonation.business, user: impersonation.user,
                       request:, session: impersonation.id, change: "#{controller_path}##{action_name}", method: request.method,
                       path: request.path, status: response.status)
  end

  def end_impersonation!(impersonation, because)
    AuditEntry.record!(operator: true_user, action: "impersonation.ended", business: impersonation.membership&.business,
                       user: impersonation.membership&.user, request:, session: impersonation.id,
                       minutes: impersonation.minutes, ended: because)
    Impersonation.clear!(warden.session(:user))
    @impersonation = nil
  end
end
