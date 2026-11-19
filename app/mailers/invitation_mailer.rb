class InvitationMailer < ApplicationMailer
  def invite
    business = Business.find(params[:business_id])
    Tenancy.with_business(business) do
      @invitation = Invitation.find(params[:invitation_id])
      @business = business
      @inviter = @invitation.invited_by unless @invitation.invited_by&.deleted? # ACC-06: not "Former member invited you"
      @url = invitation_url(@invitation.token)
    end
    mail to: @invitation.email, reply_to: @inviter&.email,
         subject: "#{@inviter&.full_name || "Someone"} invited you to #{@business.name} on Shadetree"
  end
end
