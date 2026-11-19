# OPS-03: while an operator views the app as a member (Impersonation), current_user is that
# member everywhere but the console, and this guard decides what may happen.
#
# Every controller says what support may do there (a test walks the routes to make sure):
#
#   impersonation :allowed, reads: %i[search]   # changes allowed in write mode; these POSTs only read
#   impersonation :read_only                    # can be looked at, never changed
#   impersonation :blocked, only: %i[show]      # not even opened (downloads, sign-in, invitations)
#
# - Read-only mode (the default): GETs, and the POSTs a controller lists as reads, only.
# - Changes allowed: also changes where a controller allows them, except a few that are always
#   refused (Owners' roles, the business's email). Every change is in the audit log.
# - Signing out ends the impersonation first. An undeclared controller is read-only.
#
# The console (Ops::) always acts as the operator. Ops::ImpersonationsController#destroy is Stop.
module ImpersonationSupport
  extend ActiveSupport::Concern

  LEVELS = %i[allowed read_only blocked].freeze

  included do
    helper_method :impersonation, :true_user
    before_action :guard_impersonation
    after_action :audit_impersonated_change
  end

  class_methods do
    def impersonation(level, only: nil, reads: [])
      raise ArgumentError, "impersonation level must be one of #{LEVELS.join(", ")}" unless LEVELS.include?(level)

      @impersonation_rules = [ *(@impersonation_rules || []), [ level, only&.map(&:to_s) ] ]
      @impersonation_reads = [ *(@impersonation_reads || []), *reads.map(&:to_s) ]
    end

    def impersonation_declared? = instance_variable_defined?(:@impersonation_rules)

    # What support may do in an action: a rule naming it, else the controller's general rule,
    # else the parent's; read-only when nothing says.
    def impersonation_level(action)
      rules = @impersonation_rules || []
      rule = rules.find { _2&.include?(action.to_s) } || rules.find { _2.nil? }
      return rule.first if rule

      superclass.respond_to?(:impersonation_level) ? superclass.impersonation_level(action) : :read_only
    end

    def impersonation_read?(action)
      (@impersonation_reads || []).include?(action.to_s) || (superclass.respond_to?(:impersonation_read?) && superclass.impersonation_read?(action))
    end
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
                         alert: "Your view as a member ended (#{because == "timed_out" ? "it timed out" : "it was stopped or access changed"}).")
    end
    return if is_a?(Ops::BaseController)
    return end_impersonation!(impersonation, "signed_out") if controller_path == "users/sessions" && action_name == "destroy" # then sign out as usual

    impersonation.touch!
    Current.impersonator = true_user
    warden.session(:user)["ops_seen_at"] = Time.current.to_i # viewing as a member is console activity
    refusal = impersonation_refusal
    refuse_while_impersonating(refusal) if refusal
  end

  def impersonation_refusal
    level = self.class.impersonation_level(action_name)
    return "Support can't open this while viewing as a member." if level == :blocked
    return if request.get? || request.head? || self.class.impersonation_read?(action_name)
    return "You're viewing in read-only mode, so nothing was changed." if impersonation.read_only?
    return "Support can't change this, even with changes allowed." if level == :read_only

    "Support can't change #{always_refused}, even with changes allowed." if always_refused
  end

  # Changes refused in write mode even where a controller allows changes.
  def always_refused
    case controller_path
    when "admin/members" then "Owners' roles" if owner_role_change?
    when "admin/businesses" then "the business's email" if params.dig(:business, :email) && params.dig(:business, :email).to_s.strip != impersonation.business.email.to_s
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

  # Each change made while viewing as a member, and what it created (where it went next).
  def audit_impersonated_change
    return if is_a?(Ops::BaseController) || impersonation.nil? || request.get? || request.head? || self.class.impersonation_read?(action_name)

    AuditEntry.record!(operator: true_user, action: "impersonation.change", business: impersonation.business, user: impersonation.user,
                       request:, session: impersonation.id, change: "#{controller_path}##{action_name}", method: request.method,
                       path: request.path, status: response.status, location: response.location&.then { URI.parse(_1).path rescue nil }) # rubocop:disable Style/RescueModifier
  end

  def end_impersonation!(impersonation, because)
    unless because == "already_ended"
      AuditEntry.record!(operator: true_user, action: "impersonation.ended", business: impersonation.membership&.business,
                         user: impersonation.membership&.user, request:, session: impersonation.id,
                         minutes: impersonation.minutes(because), ended: because)
    end
    Impersonation.clear!(warden.session(:user))
    @impersonation = nil
  end
end
