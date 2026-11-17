# The Shadetree-branded platform layout (NTF-01): team invitations use it.
class InvitationMailerPreview < ActionMailer::Preview
  def invite
    business = Business.order(:id).first
    invitation = Tenancy.with_business(business) { Invitation.order(:id).last }
    return ActionMailer::Base.mail(to: "nobody@example.com", subject: "No invitation yet", body: "Invite someone in development first.") unless invitation

    InvitationMailer.with(business_id: business.id, invitation_id: invitation.id).invite
  end
end
