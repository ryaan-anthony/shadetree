# ACC-09: a member's profile in this business. Anyone edits their own (from the user menu);
# people who manage the team edit others' from the Team page, and only those who manage Owners
# edit an Owner's (ACC-07's rule). A change by someone else is recorded and the member is told.
class Admin::ProfilesController < Admin::BaseController
  # OPS-03: support viewing as a member sees profiles but never changes them
  impersonation :read_only
  allow_any_member
  before_action :set_member

  def edit; end

  def update
    @member.assign_attributes(params.require(:business_user).permit(:photo, :remove_photo, :title, :bio, :work_phone))
    changed = @member.profile_changes
    if @member.save
      record_change(changed) if changed.any? && !own?
      redirect_to (own? ? edit_admin_profile_path : admin_team_path), notice: changed.any? ? "Profile saved." : "Nothing changed."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def own? = @member == current_membership

  # Someone else's profile is looked up through this business only.
  def set_member
    return @member = current_membership unless params[:member_id]

    @member = current_business.business_users.includes(:user).find_by!(uid: params[:member_id].to_s)
    return redirect_to(admin_team_path, alert: "That person deleted their Shadetree account.") if @member.user.deleted? # ACC-06

    deny!(@member.owner? ? :manage_owners : :manage_team, "editing another member's profile") unless current_membership.can_edit_profile?(@member)
  end

  def record_change(changed)
    ProfileEvent.record!(@member, changed, by: current_user)
    what = changed.map { TeamProfile::FIELDS.fetch(_1) }.to_sentence
    NotificationType.deliver("profile_changed", business: current_business, subject: @member, actor: current_user, to: [ @member.user ],
                                                title: "#{current_user.full_name} changed your #{what} in #{current_business.name}", path: edit_admin_profile_path)
  end
end
