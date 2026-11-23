# ACC-09: team members' faces and titles on staff pages. The business's memberships, with their
# photos, are loaded once a request, so lists don't query per person.
module TeamHelper
  # { user_id => BusinessUser } for the current business, photos preloaded.
  def team_profiles
    @team_profiles ||= current_business ? current_business.business_users.with_attached_photo.includes(:user).index_by(&:user_id) : {}
  end

  # A user's photo or initials in this business (decorative beside their name by default).
  def user_avatar(user, size: :sm, decorative: true, **attributes)
    member = team_profiles[user.id]
    return member_avatar(member, size:, decorative:, **attributes) if member

    classes = [ ("avatar-#{size}" unless size == :sm), attributes.delete(:class) ].compact.join(" ").presence
    avatar(user.full_name, class: classes, "aria-hidden": true, **attributes)
  end

  def user_title(user) = team_profiles[user.id]&.title
end
