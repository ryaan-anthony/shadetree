# OPS-03: viewing the app as a member. Starting needs a reason and a fresh code; allowing
# changes needs a second reason; stopping always works. Each step is audited.
class Ops::ImpersonationsController < Ops::BaseController
  skip_before_action :expire_idle_session, :require_two_factor, only: :destroy # Stop always works
  before_action :require_recent_verification, only: :create
  before_action :require_recent_verification, only: :update, if: -> { params[:mode] == "write" }
  before_action :require_impersonation, only: %i[edit update destroy]

  def create
    business = Business.find_by!(uid: params[:business_id].to_s)
    back = ops_business_path(business, anchor: "view-as")
    return redirect_to(back, alert: "You're already viewing the app as someone. Stop that first.") if impersonation
    return redirect_to(back, alert: "Give a reason for viewing as this member.") if params[:reason].blank?

    membership = business.business_users.includes(:user).find_by(uid: params[:member].to_s)
    refusal = Impersonation.refusal_for(membership, operator: current_user)
    return redirect_to(back, alert: refusal) if refusal

    session = Impersonation.start!(ops_session, operator: current_user, membership:)
    audit!("impersonation.started", business:, user: membership.user, reason: params[:reason].to_s.strip.first(500),
                                    session: session.id, role: membership.role_name, mode: "read_only")
    redirect_to admin_root_path, notice: "You're viewing the app as #{membership.user.full_name}, read-only."
  end

  # Choosing whether changes are allowed.
  def edit; end

  def update
    mode = params[:mode] == "write" ? "write" : "read_only"
    if mode == "write" && params[:reason].blank?
      flash.now[:alert] = "Give a reason for allowing changes."
      return render(:edit, status: :unprocessable_content)
    end

    impersonation.mode = mode
    audit!(mode == "write" ? "impersonation.changes_allowed" : "impersonation.read_only", business: impersonation.business,
           user: impersonation.user, reason: (params[:reason].to_s.strip.first(500) if mode == "write"), session: impersonation.id)
    redirect_to admin_root_path, notice: mode == "write" ? "Changes are allowed. Account, billing and Owner settings stay blocked." : "Back to read-only."
  end

  def destroy
    business = impersonation.business
    end_impersonation!(impersonation, "stopped")
    redirect_to ops_business_path(business), notice: "You've stopped viewing as a member."
  end

  private

  def require_impersonation
    redirect_to ops_root_path, alert: "You aren't viewing the app as anyone." unless impersonation
  end
end
