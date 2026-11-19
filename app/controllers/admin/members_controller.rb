# Change a member's role, deactivate or reactivate them (ACC-03, ACC-04 rules).
class Admin::MembersController < Admin::BaseController
  requires_permission :manage_team
  before_action :set_member

  def update
    role = params.require(:member).fetch(:role)
    return deny_change unless current_membership.can_assign_role?(@member, role)

    if @member.update(role:)
      redirect_to admin_team_path, notice: "#{@member.user.full_name} is now #{role == "admin" ? "an" : "a"} #{role}."
    else
      redirect_to admin_team_path, alert: @member.errors.full_messages.to_sentence
    end
  end

  def deactivate
    return deny_change unless current_membership.can_assign_role?(@member, @member.role)
    return redirect_to(admin_team_path, alert: "You can't deactivate yourself.") if @member == current_membership

    if @member.deactivate!
      redirect_to admin_team_path, notice: "#{@member.user.full_name} no longer has access."
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_team_path, alert: @member.errors.full_messages.to_sentence
  end

  def reactivate
    return deny_change unless current_membership.can_assign_role?(@member, @member.role)
    # BIL-01: a reactivated member counts toward the plan's team size again.
    entitlements = current_business.entitlements
    return redirect_to(admin_team_path, alert: entitlements.team_limit_message) unless entitlements.within?(:team_members)
    return redirect_to(admin_team_path, alert: "That person deleted their Shadetree account.") if @member.user.deleted? # ACC-06

    @member.reactivate!
    redirect_to admin_team_path, notice: "#{@member.user.full_name} has access again as #{@member.role}."
  end

  private

  # Members are looked up through the current business only.
  def set_member
    @member = current_business.business_users.includes(:user).find_by!(uid: params[:id].to_s)
  end

  def deny_change = redirect_to(admin_team_path, alert: "Only owners can change owners.")
end
