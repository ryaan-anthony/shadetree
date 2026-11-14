# Invite people, resend and revoke invitations (ACC-03).
class Admin::InvitationsController < Admin::BaseController
  requires_permission :manage_team
  before_action :require_confirmed_sender, only: %i[create resend]
  before_action :set_invitation, only: %i[resend revoke]
  rate_limit to: 30, within: 1.hour, only: :create, by: -> { current_user.id },
             with: -> { redirect_to admin_team_path, alert: "That's a lot of invitations. Try again in a little while." }

  def create
    @invitation = Invitation.new(invitation_params.merge(invited_by: current_user))
    unless current_membership.can_assign_role?(BusinessUser.new(business: current_business, role: "technician"), @invitation.role)
      return redirect_to admin_team_path, alert: "Only owners can invite owners."
    end

    if @invitation.save
      @invitation.deliver!
      redirect_to admin_team_path, notice: "Invitation sent to #{@invitation.email}."
    else
      redirect_to admin_team_path, alert: @invitation.errors.full_messages.to_sentence
    end
  end

  def resend
    @invitation.resend!
    redirect_to admin_team_path, notice: "Invitation resent to #{@invitation.email}. It now expires in 7 days."
  end

  def revoke
    @invitation.revoke!
    redirect_to admin_team_path, notice: "Invitation to #{@invitation.email} revoked."
  end

  private

  def set_invitation = @invitation = Invitation.find_by_param!(params[:id])

  def invitation_params = params.require(:invitation).permit(:email, :role)
end
