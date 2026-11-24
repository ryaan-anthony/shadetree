# The team page: members, pending invitations and deactivated people (ACC-03).
class Admin::TeamController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :manage_team

  def show
    memberships = current_business.business_users.includes(:user).order("users.first_name", "users.email")
    @active = memberships.active
    @deactivated = memberships.deactivated
    @invitations = Invitation.where(accepted_at: nil, revoked_at: nil).includes(:invited_by).order(created_at: :desc)
    @invitation = Invitation.new(role: "technician")
    @custom_roles = Role.ordered.to_a # ACC-07
    # ACC-09: changes teammates made to each profile, newest first, in one query
    @profile_history = ProfileEvent.where(business_user_id: memberships.map(&:id)).includes(:user).order(occurred_at: :desc, id: :desc).group_by(&:business_user_id)
    @support_visits = AuditEntry.support_visits(current_business) if current_membership.owner? # OPS-03
  end
end
