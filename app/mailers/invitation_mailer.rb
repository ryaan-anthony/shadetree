class InvitationMailer < ApplicationMailer
  def invite
    @invitation = params[:invitation]
    @business = @invitation.business
    @inviter = @invitation.invited_by
    @url = invitation_url(@invitation.token)
    mail to: @invitation.email, reply_to: @inviter.email,
         subject: "#{@inviter.full_name} invited you to #{@business.name} on Shadetree"
  end
end
