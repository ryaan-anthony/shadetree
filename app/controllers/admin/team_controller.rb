# The team page: members, pending invitations and deactivated people (ACC-03).
class Admin::TeamController < Admin::BaseController
  requires_permission :manage_team

  def show
    memberships = current_business.business_users.includes(:user).order("users.first_name", "users.email")
    @active = memberships.active
    @deactivated = memberships.deactivated
    @invitations = Invitation.where(accepted_at: nil, revoked_at: nil).includes(:invited_by).order(created_at: :desc)
    @invitation = Invitation.new(role: "technician")
    @custom_roles = Role.ordered.to_a # ACC-07
  end
end
